import Foundation

/// Curated models per vendor, loaded from `Resources/ProviderModels.json`
/// (kept in step with konjac's catalog of the same shape; the first entry of
/// a list is the suggested default). The Settings window offers only the
/// chosen vendor's models; API vendors can also be refreshed live
/// (`GatewayModelCatalogService`), and any id can still be typed as custom.
public enum ModelCatalog {
  public static func models(for vendor: String) -> [String] {
    catalog.vendors[vendor] ?? []
  }

  /// The vendor's first curated model, or nil when it has no list.
  public static func defaultModel(for vendor: String) -> String? {
    models(for: vendor).first
  }

  /// Vendors whose model list can be fetched live (API vendors with a key).
  public static func supportsListing(_ vendor: String) -> Bool {
    ["openai", "anthropic", "gemini", "openrouter"].contains(vendor)
  }

  public static var updatedAt: String { catalog.updatedAt }

  private static let catalog = loadCatalog()

  private static func loadCatalog() -> Catalog {
    guard let url = Bundle.module.url(forResource: "ProviderModels", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(Catalog.self, from: data) else {
      assertionFailure("ProviderModels.json is missing or invalid in StriaCore resources")
      return Catalog(updatedAt: "", vendors: [:])
    }
    return decoded
  }

  private struct Catalog: Decodable, Sendable {
    let updatedAt: String
    let vendors: [String: [String]]
  }
}
