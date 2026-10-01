import StriaCore

if CommandLine.arguments.contains("--version") {
  print(Version.current)
} else {
  print("Usage: stria <command>")
}
