import Foundation

/// Curated models per vendor (the first entry of a list is the suggested
/// default). Kept in code rather than a resource bundle so the signed
/// Stria.app and the CLI need no SwiftPM resource bundle beside them. The
/// vendor lists follow konjac's ProviderModels.json; Claude ids follow
/// Anthropic's current catalog. The Settings window offers only the chosen
/// vendor's models; API vendors can also be refreshed live
/// (`GatewayModelCatalogService`), and any id can still be typed as custom.
public enum ModelCatalog {
  public static let updatedAt = "2026-10-02"

  private static let vendors: [String: [String]] = [
    "anthropic": ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-haiku-4-5-20251001"],
    "claude-code": ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-haiku-4-5-20251001"],
    "openai": ["gpt-6-luna", "gpt-6-sol", "gpt-6-astra"],
    "codex": ["gpt-6-luna", "gpt-6-sol", "gpt-6-astra"],
    "gemini": ["gemini-3.5-flash-lite", "gemini-3.8-flash"],
    "openrouter": [
      "anthropic/claude-opus-5-5",
      "anthropic/claude-sonnet-5-5",
      "anthropic/claude-fable-5-1",
      "anthropic/claude-haiku-4-5-20251001",
      "openai/gpt-6-luna",
      "openai/gpt-6-sol",
      "openai/gpt-6-astra",
      "google/gemini-3.5-flash-lite",
      "google/gemini-3.8-flash"
    ],
    "cursor": [],
    "cursor-api": []
  ]

  public static func models(for vendor: String) -> [String] {
    vendors[vendor] ?? []
  }

  /// The vendor's first curated model, or nil when it has no list.
  public static func defaultModel(for vendor: String) -> String? {
    models(for: vendor).first
  }

  /// Vendors whose model list can be fetched live (API vendors with a key).
  public static func supportsListing(_ vendor: String) -> Bool {
    ["openai", "anthropic", "gemini", "openrouter"].contains(vendor)
  }
}
