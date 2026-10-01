# agent-gateway API at `c7f269753ec36aca92d429ec13316ba033128967`

Resolved by SwiftPM from `https://github.com/tacogips/agent-gateway.git`; checkout: `.build/checkouts/agent-gateway`. The package declares products `AgentGateway`, `AgentGatewayAppCore`, and `ACP` in `Package.swift`.

The declarations below are copied as API signatures only from that checkout.

## Vendor and defaults

`Sources/AgentGateway/GatewayProtocol.swift`:

```swift
public enum GatewayVendor: String, Codable, CaseIterable, Sendable {
  case claudeCode = "claude-code", codex, cursor
  case cursorAPI = "cursor-api", openAI = "openai", anthropic, gemini
  case openRouter = "openrouter"
}
```

`Sources/AgentGatewayAppCore/GatewayACPAgent.swift`:

```swift
public struct GatewayAgentDefaults: Equatable, Sendable {
  public init(vendor: GatewayVendor? = nil, model: String? = nil,
    systemPrompt: String? = nil, executable: String? = nil,
    arguments: [String] = [], providerName: String? = nil,
    apiKeyEnvironment: String? = nil, baseURL: String? = nil,
    maxTokens: Int? = nil, cursorAPI: GatewayCursorAPIOptions? = nil)
}

public actor GatewayACPAgent: ACPAgent {
  public init(defaults: GatewayAgentDefaults = GatewayAgentDefaults(),
    executor: any GatewayExecuting = ProductionGatewayExecutor())
}
```

`Sources/AgentGatewayAppCore/GatewayExecution.swift`:

```swift
public struct ProductionGatewayExecutor: GatewayExecuting, GatewayReadinessChecking {
  public init(environment: [String: String] = ProcessInfo.processInfo.environment,
    processRunner: any GatewayProcessRunning = POSIXGatewayProcessRunner(),
    processOwnership: GatewayProcessOwnership = .foregroundProcessGroup)
}
```

## ACP connection and requests

`Sources/ACP/ACPClient.swift`:

```swift
public static func inProcess(agent: any ACPAgent,
  delegate: (any ACPClientDelegate)? = nil) async
  -> (client: ACPClientConnection, server: ACPAgentServer)

public func initialize(_ request: ACPInitializeRequest = ACPInitializeRequest()) async throws -> ACPInitializeResponse
public func newSession(_ request: ACPNewSessionRequest) async throws -> ACPNewSessionResponse
public func promptCollecting(_ request: ACPPromptRequest) async throws -> ACPPromptResult
```

`Sources/ACP/ACPTypes.swift`:

```swift
public struct ACPNewSessionRequest: Codable, Equatable, Sendable {
  public init(cwd: String, mcpServers: [ACPMCPServer] = [], meta: ACPJSONValue? = nil)
}
public struct ACPPromptRequest: Codable, Equatable, Sendable {
  public init(sessionId: ACPSessionID, prompt: [ACPContentBlock], meta: ACPJSONValue? = nil)
}
public enum ACPStopReason: String, Codable, Sendable {
  case endTurn = "end_turn", maxTokens = "max_tokens", maxTurnRequests = "max_turn_requests"
  case refusal, cancelled
}
```

`Sources/ACP/ACPClient.swift`:

```swift
public struct ACPPromptResult: Equatable, Sendable {
  public var response: ACPPromptResponse
  public var messageText: String
  public var thoughtText: String
  public var updates: [ACPSessionUpdate]
}
```

`Sources/ACP/ACPContent.swift` provides `ACPContentBlock.text(ACPTextContent)`, the convenience `ACPContentBlock.text(_ value: String)`, and `.image(ACPImageContent)`.

## Image inputs and process errors

`Sources/AgentGatewayAppCore/GatewayACPClientRunner.swift`:

```swift
public enum GatewayClientImageInput: Equatable, Sendable {
  case filePath(String)
  case data(mimeType: String, base64: String)
}
public func gatewayImageContentBlocks(_ images: [GatewayClientImageInput]) throws -> [ACPContentBlock]
```

`gatewayImageContentBlocks` reads and validates `.filePath`, converts the bytes to inline base64 ACP image blocks, and retains the file URI. Gateway API serialization supports those images for `openai`, `anthropic`, `gemini`, and `openrouter`; `cursor-api` explicitly rejects gateway image inputs. CLI vendor requests use ACP image blocks.

`Sources/AgentGatewayAppCore/GatewayProcessContracts.swift` declares the process-launch error:

```swift
public enum GatewayProcessError: Error, Equatable, Sendable {
  case unsupportedOwnership(GatewayProcessOwnership), invalidRequest, launchFailed(Int32)
  case ownershipLost(Int32), timedOut, ioFailed(Int32), cleanupFailed(Int32)
}
```

The `launchFailed(Int32)` case reports process launch failure. P01 keeps all gateway types out of StriaCore; adapters belong to P05.
