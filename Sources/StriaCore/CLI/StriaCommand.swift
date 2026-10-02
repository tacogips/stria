import Foundation

public enum StriaCommand {
  public typealias ServiceFactory = @Sendable (StriaPaths, StriaConfig) -> (any OCRService, any AgentService)

  public static func run(
    arguments: [String],
    environment: [String: String],
    homeDirectory: URL,
    currentDirectory: URL,
    services: ServiceFactory
  ) async -> CommandOutput {
    let invocation: ParsedInvocation
    do {
      invocation = try CommandLineParser.parse(arguments)
    } catch {
      return CLIJSON.failure(error)
    }

    switch invocation.command {
    case .help(let topic): return CommandOutput(stdout: Usage.text(for: topic), stderr: "", exitCode: 0)
    case .version: return CommandOutput(stdout: Version.current + "\n", stderr: "", exitCode: 0)
    default: break
    }

    do {
      let paths = StriaPaths.resolve(homeFlag: invocation.home, environment: environment,
                                     homeDirectory: homeDirectory, currentDirectory: currentDirectory)
      var config = try ConfigStore.loadOrCreate(paths: paths)
      let selected = services(paths, config)
      let warning = RunLogWarning()
      let env = StriaEnvironment(paths: paths, config: config, ocrService: selected.0, agentService: selected.1,
                                 onRunLogFailure: { warning.set($0) })
      let library = try StriaLibrary.open(environment: env)
      let value: any Encodable
      switch invocation.command {
      case .importPDF, .ocr, .list, .show, .remove, .pageImage, .pageText:
        value = try await DocumentCommands.run(invocation.command, library: library, currentDirectory: currentDirectory)
      case .search, .ask, .history:
        value = try await QueryCommands.run(invocation.command, library: library)
      case .configGet, .configSet, .paths:
        value = try ConfigCommands.run(invocation.command, config: &config, paths: paths)
      case .help, .version:
        throw StriaError.usage("Unexpected early command")
      }
      var output = try CLIJSON.success(AnyEncodable(value))
      if let message = warning.get() { output.stderr = "warning: run log append failed: \(message)\n" }
      return output
    } catch let error as StriaError {
      return CLIJSON.failure(error)
    } catch is CancellationError {
      return CLIJSON.failure(.io("Cancelled"))
    } catch {
      return CLIJSON.failure(.io(String(describing: error)))
    }
  }
}

private struct AnyEncodable: Encodable {
  private let encodeValue: (Encoder) throws -> Void
  init(_ value: any Encodable) { encodeValue = value.encode }
  func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

private final class RunLogWarning: @unchecked Sendable {
  private let lock = NSLock()
  private var message: String?

  func set(_ value: String) {
    lock.lock()
    defer { lock.unlock() }
    if message == nil { message = value }
  }

  func get() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return message
  }
}
