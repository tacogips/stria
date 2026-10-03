import Foundation
@testable import StriaCore
import Testing

@Suite struct LoginEnvironmentTests {
  @Test func additionsFillMissingVariablesAndPrependLoginPath() {
    let current = ["PATH": "/usr/bin:/bin", "HOME": "/Users/x"]
    let login = ["PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/other", "OPENAI_API_KEY": "k", "PWD": "/tmp", "SHLVL": "2"]
    let additions = LoginEnvironment.additions(current: current, login: login)
    #expect(additions["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
    #expect(additions["OPENAI_API_KEY"] == "k")
    #expect(additions["HOME"] == nil)
    #expect(additions["PWD"] == nil)
    #expect(additions["SHLVL"] == nil)
  }

  @Test func parsesNulSeparatedEnvAndDetectsTerminalLaunch() {
    let data = Data("A=1\0B=x=y\0broken\0".utf8)
    #expect(LoginEnvironment.parse(data) == ["A": "1", "B": "x=y"])
    #expect(!LoginEnvironment.isGUILaunch(["TERM": "xterm"]))
    #expect(LoginEnvironment.isGUILaunch([:]))
    #expect(!LoginEnvironment.isGUILaunch(["STRIA_SKIP_LOGIN_ENV": "1"]))
  }

  @Test func capturesFromARealShell() {
    let env = LoginEnvironment.capture(shell: "/bin/sh", timeout: 5)
    #expect(env["PATH"] != nil)
  }
}
