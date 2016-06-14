import os, future


# TODO: Allow rule to have specific set of allowed commands after it.
# Example: --foo bar baz
# TODO: Add syntax for turning arguments into a list
# Example: --foo=[1, 2, 3] -> @[1, 2, 3]
# Example: --foo [1, 2, 3] -> @[1, 2, 3]
# Example: --foo=1,2,3 -> @[1, 2, 3]
# TODO: Write tests.


type
  ParseException* = object of Exception

  CommandParser* = object
    callback*: (param: string, values: seq[string]) -> void
    cmd: seq[TaintedString]
    curIdx: int
    valueDelimiters: seq[char]
    rules: seq[CommandRule]
    helpText: string

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


proc `$`*(commandParser: CommandParser): string =
  "CommandParser{cmd:" & $commandParser.cmd &
    "; curIdx:" & $commandParser.curIdx &
    "; valueDelimiters:" & $commandParser.valueDelimiters &
    "; rules:" & $commandParser.rules &
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

proc newCommandRule(name: string, kind: CommandRuleType, allowSpace: bool = false, allowNoDelimiter: bool = false): CommandRule =
  CommandRule(name: name, kind: kind, value: nil, allowSpace: allowSpace, allowNoDelimiter: allowNoDelimiter)

proc addShortRule*(parser: var CommandParser, argName: string, allowNoDelimiter: bool = false) =
  parser.rules.add(newCommandRule(argName, ruleShort, allowNoDelimiter = allowNoDelimiter))

proc addLongRule*(parser: var CommandParser, argName: string, allowSpace: bool = false) =
  parser.rules.add(newCommandRule(argName, ruleLong, allowSpace = allowSpace))

proc addBothRules*(parser: var CommandParser, argNames: array[2, string], allowSpace: bool = false, allowNoDelimiter: bool = false) =
  parser.addShortRule(argNames[0], allowNoDelimiter = allowNoDelimiter)
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
  if parser.callback == nil:
    raise newException(ParseException, "No callback given for parsing!")

  try:
    for arg in parser.cmd:
      if arg[0] == '-':
        if arg[1] == '-':
          # Long argument path
          # Example: --test
          # Example: --test=FOO_BAR
          # Example: --test:FOO_BAR
          # Example: --test FOO_BAR
          var
            value: string
            rule: CommandRule
            baseArg: string
            valueInArg = false

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
          echo "Short arg: ", arg
      else:
        # Commang argument path
        # Example: foobar
        echo "Command arg: ", arg

      parser.curIdx += 1
  except ParseException:
    if parser.helpText == nil:
      parser.helpText = parser.autogenHelpText()
    echo getCurrentExceptionMsg()
    echo parser.helpText


when isMainModule:
  proc testParseCallback1(arg: string, values: seq[string]) =
    echo "callback arg: ", arg, ", value: ", $values

  var parser = newCommandParser()
  parser.addLongRule("test", allowSpace = true)
  parser.addLongRule("foo")
  parser.addShortRule("t")
  parser.addShortRule("f", allowNoDelimiter = true)
  parser.callback = testParseCallback1
  parser.parse()
  echo $parser
