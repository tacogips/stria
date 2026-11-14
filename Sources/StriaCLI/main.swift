import StriaCore
import Foundation

let output = await StriaCommand.run(
  arguments: Array(CommandLine.arguments.dropFirst()),
  environment: ProcessInfo.processInfo.environment,
  homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
  currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
  services: StriaEnvironment.liveServices(paths:config:)
)
if let data = output.stdout.data(using: .utf8) { FileHandle.standardOutput.write(data) }
if let data = output.stderr.data(using: .utf8) { FileHandle.standardError.write(data) }
exit(output.exitCode)
