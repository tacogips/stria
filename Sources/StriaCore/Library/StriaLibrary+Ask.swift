import Foundation

extension StriaLibrary {
  public func ask(_ request: AskRequest) async throws -> AskResponse {
    try await AskCoordinator(environment: environment, store: store).ask(request)
  }
}
