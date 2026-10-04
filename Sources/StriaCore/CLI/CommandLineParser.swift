public enum CommandLineParser {
  public static func parse(_ arguments: [String]) throws(StriaError) -> ParsedInvocation {
    var home: String?
    var tokens: [String] = []
    var index = 0

    while index < arguments.count {
      let token = arguments[index]
      if token == "--home" {
        guard home == nil else { throw .usage("--home may be specified only once") }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          throw .usage("--home requires a path value")
        }
        home = arguments[index + 1]
        index += 2
      } else if token == "--json" {
        index += 1
      } else {
        tokens.append(token)
        index += 1
      }
    }

    if tokens.contains("--version") { return ParsedInvocation(home: home, command: .version) }
    if tokens.isEmpty { return ParsedInvocation(home: home, command: .help(topic: nil)) }
    if tokens.contains("--help") || tokens.contains("-h") {
      return ParsedInvocation(home: home, command: .help(topic: tokens.first(where: { !$0.hasPrefix("-") })))
    }

    let command = tokens.removeFirst()
    let parsed = try parseCommand(command, arguments: tokens)
    return ParsedInvocation(home: home, command: parsed)
  }

  private static func parseCommand(_ command: String, arguments: [String]) throws(StriaError) -> CLICommand {
    switch command {
    case "import":
      let parsed = try options(arguments, flags: ["--no-ocr", "--ocr"], values: [], command: command)
      try requirePositionals(parsed.positionals, count: 1, command: command)
      if parsed.flags.contains("--no-ocr") && parsed.flags.contains("--ocr") { throw .usage("--ocr and --no-ocr are exclusive") }
      return .importPDF(path: parsed.positionals[0], noOCR: parsed.flags.contains("--no-ocr"), forceOCR: parsed.flags.contains("--ocr"))
    case "ocr":
      let parsed = try options(arguments, flags: ["--retry-failed"], values: ["--pages"], command: command)
      try requirePositionals(parsed.positionals, count: 1, command: command)
      return .ocr(docId: parsed.positionals[0], pages: parsed.values["--pages"], retryFailed: parsed.flags.contains("--retry-failed"))
    case "list":
      try rejectOptions(arguments, command: command)
      try requirePositionals(arguments, count: 0, command: command)
      return .list
    case "show":
      let parsed = try options(arguments, flags: [], values: [], command: command)
      try requirePositionals(parsed.positionals, count: 1, command: command)
      return .show(docId: parsed.positionals[0])
    case "remove":
      let parsed = try options(arguments, flags: [], values: [], command: command)
      try requirePositionals(parsed.positionals, count: 1, command: command)
      return .remove(docId: parsed.positionals[0])
    case "page":
      guard let subcommand = arguments.first else { throw .usage("page requires image or text") }
      let rest = Array(arguments.dropFirst())
      switch subcommand {
      case "image":
        let parsed = try options(rest, flags: [], values: ["--output"], command: "page image")
        try requirePositionals(parsed.positionals, count: 2, command: "page image")
        return .pageImage(docId: parsed.positionals[0], page: try positiveInteger(parsed.positionals[1], name: "page"), output: parsed.values["--output"])
      case "text":
        let parsed = try options(rest, flags: [], values: [], command: "page text")
        try requirePositionals(parsed.positionals, count: 2, command: "page text")
        return .pageText(docId: parsed.positionals[0], page: try positiveInteger(parsed.positionals[1], name: "page"))
      default: throw .usage("Unknown page command '\(subcommand)'; expected image or text")
      }
    case "search":
      let parsed = try options(arguments, flags: [], values: ["--doc", "--limit"], command: command)
      try requirePositionals(parsed.positionals, count: 1, command: command)
      let limit = try optionalPositiveInteger(parsed.values["--limit"], name: "--limit")
      return .search(query: parsed.positionals[0], docId: parsed.values["--doc"], limit: limit)
    case "ask":
      let parsed = try options(arguments, flags: [], values: ["--doc", "--page", "--query", "--limit", "--thread", "--vendor", "--model"], command: command)
      if parsed.values["--model"] != nil && parsed.values["--vendor"] == nil { throw .usage("--model requires --vendor") }
      try requirePositionals(parsed.positionals, count: 1, command: command)
      if parsed.values["--page"] != nil && parsed.values["--doc"] == nil { throw .usage("--page requires --doc") }
      let page = try optionalPositiveInteger(parsed.values["--page"], name: "--page")
      let limit = try optionalPositiveInteger(parsed.values["--limit"], name: "--limit")
      return .ask(question: parsed.positionals[0], docId: parsed.values["--doc"], page: page, query: parsed.values["--query"],
                  limit: limit, thread: parsed.values["--thread"], vendor: parsed.values["--vendor"], model: parsed.values["--model"])
    case "history":
      let parsed = try options(arguments, flags: ["--threads"], values: ["--doc", "--page", "--limit"], command: command)
      try requirePositionals(parsed.positionals, count: 0, command: command)
      if parsed.values["--page"] != nil && parsed.values["--doc"] == nil { throw .usage("--page requires --doc") }
      let page = try optionalPositiveInteger(parsed.values["--page"], name: "--page")
      let limit = try optionalPositiveInteger(parsed.values["--limit"], name: "--limit")
      return .history(docId: parsed.values["--doc"], page: page, limit: limit, threads: parsed.flags.contains("--threads"))
    case "config":
      guard let subcommand = arguments.first else { return .configGet(key: nil) }
      switch subcommand {
      case "get":
        let rest = Array(arguments.dropFirst())
        try rejectOptions(rest, command: "config get")
        try requirePositionals(rest, count: 0...1, command: "config get")
        return .configGet(key: rest.first)
      case "set":
        let rest = Array(arguments.dropFirst())
        try rejectOptions(rest, command: "config set")
        try requirePositionals(rest, count: 2, command: "config set")
        return .configSet(key: rest[0], value: rest[1])
      default: throw .usage("Unknown config command '\(subcommand)'; expected get or set")
      }
    case "paths":
      try rejectOptions(arguments, command: command)
      try requirePositionals(arguments, count: 0, command: command)
      return .paths
    default: throw .usage("Unknown command '\(command)'")
    }
  }

  private struct ParsedOptions {
    var positionals: [String] = []
    var flags: Set<String> = []
    var values: [String: String] = [:]
  }

  private static func options(
    _ arguments: [String], flags: Set<String>, values: Set<String>, command: String
  ) throws(StriaError) -> ParsedOptions {
    var result = ParsedOptions()
    var index = 0
    while index < arguments.count {
      let token = arguments[index]
      if flags.contains(token) {
        guard !result.flags.contains(token) else { throw .usage("Duplicate option \(token)") }
        result.flags.insert(token)
        index += 1
      } else if values.contains(token) {
        guard result.values[token] == nil else { throw .usage("Duplicate option \(token)") }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
          throw .usage("\(token) requires a value")
        }
        result.values[token] = arguments[index + 1]
        index += 2
      } else if token.hasPrefix("-") {
        throw .usage("Unknown option \(token) for \(command)")
      } else {
        result.positionals.append(token)
        index += 1
      }
    }
    return result
  }

  private static func rejectOptions(_ arguments: [String], command: String) throws(StriaError) {
    if let option = arguments.first(where: { $0.hasPrefix("-") }) {
      throw .usage("Unknown option \(option) for \(command)")
    }
  }

  private static func requirePositionals(_ values: [String], count: Int, command: String) throws(StriaError) {
    try requirePositionals(values, count: count...count, command: command)
  }

  private static func requirePositionals(_ values: [String], count: ClosedRange<Int>, command: String) throws(StriaError) {
    guard count.contains(values.count) else {
      let expected = count.lowerBound == count.upperBound ? "\(count.lowerBound)" : "\(count.lowerBound)...\(count.upperBound)"
      throw .usage("\(command) expects \(expected) positional argument(s), got \(values.count)")
    }
  }

  private static func positiveInteger(_ value: String, name: String) throws(StriaError) -> Int {
    guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(value), number > 0 else {
      throw .usage("\(name) must be a positive decimal integer: '\(value)'")
    }
    return number
  }

  private static func optionalPositiveInteger(_ value: String?, name: String) throws(StriaError) -> Int? {
    guard let value else { return nil }
    return try positiveInteger(value, name: name)
  }
}
