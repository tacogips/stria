import Foundation
import KaibaViewerCore

let command = KaibaViewerCommand(arguments: Array(CommandLine.arguments.dropFirst()))

do {
  let output = try command.run()
  if !output.isEmpty {
    print(output)
  }
} catch KaibaViewerCommand.Error.unknownArgument(let argument) {
  FileHandle.standardError.write(Data("Unknown argument: \(argument)\n".utf8))
  exit(2)
} catch {
  FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
  exit(1)
}
