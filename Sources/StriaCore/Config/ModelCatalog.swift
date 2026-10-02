import Foundation

/// Known models per vendor, so the Settings window offers only models that
/// belong to the chosen vendor. The list is a starting point: API vendors
/// can be refreshed from their model-listing endpoint
/// (`GatewayModelCatalogService`), and any id can still be typed as a
/// custom model.
public enum ModelCatalog {
  public static func models(for vendor: String) -> [String] {
    switch vendor {
    case "claude-code", "anthropic":
      ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-haiku-4-5-20251001"]
    case "codex", "openai":
      ["gpt-6-luna", "gpt-5", "gpt-5-mini"]
    case "gemini":
      ["gemini-2.5-pro", "gemini-2.5-flash"]
    case "openrouter":
      ["anthropic/claude-sonnet-5-5", "anthropic/claude-opus-5-5", "openai/gpt-5", "google/gemini-2.5-pro"]
    default:
      []
    }
  }

  /// Vendors whose model list can be fetched live (API vendors with a key).
  public static func supportsListing(_ vendor: String) -> Bool {
    ["openai", "anthropic", "gemini", "openrouter"].contains(vendor)
  }
}
