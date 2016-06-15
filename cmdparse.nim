import os, future


# TODO: Allow rule to have specific set of allowed commands after it.
# Example: --foo bar baz        -> WORKS
#      BUT --foo bar baz barbaz -> DOES NOT
# TODO: Add syntax for turning arguments into a list
# Example: --foo=[1, 2, 3] -> @[1, 2, 3]
# Example: --foo [1, 2, 3] -> @[1, 2, 3]
# Example: --foo=1,2,3 -> @[1, 2, 3]
# TODO: Write tests.
# TODO: Make exceptions have the message be something that can be output to command line.
# Basic idea is to have the exception being thrown be what gets shown to the use so they
# know how they used the command line arguments wrong. Instead of being something for
# the developers.
# TODO: Iterator over command line arguments in the callback format: (string, seq[string])
# Returned as tuple.
# Should return arguments in the same order they would be when being parsed with a callback.
# Example: --foo:bar -b -> ("foo", @["bar"]), ("b", @[]) every time.


type
  ParseException* = object of Exception

  CommandParser* = object
    callback*: (param: string, values: seq[string]) -> void
    cmd: seq[TaintedString]
    curIdx: int
    valueDelimiters: seq[char]
    rules: seq[CommandRule]
    helpText: string
    parsed: bool

  CommandRuleType = enum
    ruleLong,
    ruleShort,
    ruleCommand

  CommandRule = object
    name: string
    kind: CommandRuleType
    exists: bool
    value: string
    allowSpace: bool
    allowNoDelimiter: bool


proc `$!`[T](t: T): string =
  if t == nil:
    "nil"
  else:
    $t

proc `$`*(commandParser: CommandParser): string =
  "CommandParser{cmd:" & $commandParser.cmd &
    "; curIdx:" & $commandParser.curIdx &
    "; valueDelimiters:" & $commandParser.valueDelimiters &
    "; rules:" & $commandParser.rules &
    "}"

proc `$`(rule: CommandRule): string =
  "CommandRule{name:" & rule.name &
    "; kind:" & $rule.kind &
    "; exists:" & $rule.exists &
    "; value:" & $!rule.value &
    "; allowSpace:" & $rule.allowSpace &
    "; allowNoDelimiter:" & $rule.allowNoDelimiter &
    "}"

proc autogenHelpText(parser: CommandParser): string =
  "TODO: Implement auto gen help text."

proc newCommandParser*(commandArgs: seq[TaintedString] = nil, helpText: string = nil): CommandParser =
  var actualArgs: seq[TaintedString]
  if commandArgs == nil:
    actualArgs = commandLineParams()
  else:
    actualArgs = commandArgs
  result = CommandParser(cmd: actualArgs, valueDelimiters: @[':', '='],
    rules: @[])

proc validateNoDelimiters(parser: CommandParser, name: string) =
  for delimiter in parser.valueDelimiters:
    if delimiter in name:
      raise newException(ParseException, "Cannot have delimiter character '" & delimiter & "' in argument '" & name & "'")

proc newCommandRule(name: string, kind: CommandRuleType, allowSpace: bool = false, allowNoDelimiter: bool = false): CommandRule =
  CommandRule(name: name, kind: kind, value: nil, allowSpace: allowSpace, allowNoDelimiter: allowNoDelimiter)

proc addShortRule*(parser: var CommandParser, argName: char, allowNoDelimiter: bool = false) =
  let stringArgName = $argName
  parser.validateNoDelimiters(stringArgName)
  parser.rules.add(newCommandRule(stringArgName, ruleShort, allowNoDelimiter = allowNoDelimiter))

proc addLongRule*(parser: var CommandParser, argName: string, allowSpace: bool = false) =
  parser.validateNoDelimiters(argName)
  parser.rules.add(newCommandRule(argName, ruleLong, allowSpace = allowSpace))

proc addBothRules*(parser: var CommandParser, argNames: array[2, string], allowSpace: bool = false, allowNoDelimiter: bool = false) =
  parser.validateNoDelimiters(argNames[0])
  parser.validateNoDelimiters(argNames[1])
  if argNames[0].len > 2:
    raise newException(ParseException, "Given a short arg when adding both that has more than one character.")
  parser.addShortRule(argNames[0][0], allowNoDelimiter = allowNoDelimiter)
  parser.addLongRule(argNames[1], allowSpace = allowSpace)

proc addCommandRule*(parser: var CommandParser, argName: string) =
  parser.rules.add(newCommandRule(argName, ruleCommand))

proc ruleFromArgName(rules: seq[CommandRule], name: string): CommandRule {.raises: [ParseException].} =
  for rule in rules:
    if rule.name == name:
      return rule
  raise newException(ParseException, "No rule for the given argument: " & name)

proc split(str: string, delimiter: char): (string, string) =
  let pos = str.find(delimiter)
  result = (str[0 .. pos - 1], str[pos + 1 .. str.len - 1])

proc parse*(parser: var CommandParser) {.raises: [ParseException, Exception].} =
  if parser.parsed:
    return
  if parser.callback == nil:
    raise newException(ParseException, "No callback given for parsing!")

  try:
    for arg in parser.cmd:
      var
        value: string
        rule: CommandRule
        baseArg: string
        valueInArg = false
      if arg[0] == '-':
        if arg[1] == '-':
          # Long argument path
          # Example: --test
          # Example: --test=FOO_BAR
          # Example: --test:FOO_BAR
          # Example: --test FOO_BAR

          # Immediately check argument for delimiters, so that we can determine what the base
          # part of the argument is.
          # Example: --foo:test -> foo
          for delimiter in parser.valueDelimiters:
            if delimiter in arg:
              let splitArg = arg[2 .. arg.len - 1].split(delimiter)
              baseArg = splitArg[0]
              value = splitArg[1]
              valueInArg = true
              break
          if not valueInArg:
            baseArg = arg[2 .. arg.len - 1]

          rule = parser.rules.ruleFromArgName(baseArg)
          if rule.kind != ruleLong:
            raise newException(ParseException, "Found long arg with non-long rule.")

          rule.exists = true
          if valueInArg:
            rule.value = value
          elif rule.allowSpace and parser.curIdx + 1 < parser.cmd.len:
            rule.value = parser.cmd[parser.curIdx + 1]

          if rule.value != nil:
            parser.callback(baseArg, @[rule.value])
          else:
            parser.callback(baseArg, @[])
        else:
          # Short argument path
          # Example: -t
          # Example: -DFOO_BAR
          # Example: -T:foo
          # Example: -T=foo
          for delimiter in parser.valueDelimiters:
            if delimiter in arg:
              baseArg = $arg[1]
              value = arg[3 .. arg.len - 1]
              valueInArg = true
              break
          if not valueInArg:
            baseArg = $arg[1]

          rule = parser.rules.ruleFromArgName(baseArg)
          if rule.kind != ruleShort:
            echo $rule
            raise newException(ParseException, "Got argument '" & arg & "' which is supposed to be a long-form argument but was declared as a short-form one.")

          if rule.allowNoDelimiter:
            value = arg[2 .. arg.len - 1]
          elif arg.len > 2 and not valueInArg:
            raise newException(ParseException, "Found argument '" & arg & "' which has more than one character.")

          rule.exists = true
          rule.value = value

          if value != nil:
            parser.callback(baseArg, @[value])
          else:
            parser.callback(baseArg, @[])
      else:
        # Commang argument path
        # Example: foobar
        rule = parser.rules.ruleFromArgName(arg)
        if rule.kind != ruleCommand:
          raise newException(ParseException, "Found argument '" & arg & "' where the rule is not a command kind.")

        rule.exists = true
        parser.callback(arg, @[])

      parser.curIdx += 1
  except ParseException:
    if parser.helpText == nil:
      parser.helpText = parser.autogenHelpText()
    echo getCurrentExceptionMsg()
    echo parser.helpText
  parser.parsed = true


when isMainModule:
  proc testParseCallback1(arg: string, values: seq[string]) =
    echo "callback arg: ", arg, ", value: ", $values

  block:
    var parser = newCommandParser()
    try:
      parser.addLongRule("foo:")
      echo("TEST 'no delimiter in rule': FAILED")
      doAssert false
    except:
      echo("TEST 'no delimiter in rule': PASSED")
      doAssert true


  block:
    var parser = newCommandParser()
    parser.addLongRule("test", allowSpace = true)
    parser.addLongRule("foo")
    parser.addShortRule('t')
    parser.addShortRule('f', allowNoDelimiter = true)
    parser.addCommandRule("comm")
    parser.callback = testParseCallback1
    parser.parse()
    echo $parser
