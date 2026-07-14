import Foundation

/// Loads the replaceable preset data artifact. A missing or malformed catalog
/// degrades to an empty browser; manual typing and photo import remain usable.
public enum BundledPresetWordCatalog {
    public static let catalog: PresetWordCatalog = {
        guard
            let url = Bundle.module.url(
                forResource: "PresetWords",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(
                PresetWordCatalog.self,
                from: data
            )
        else {
            return .empty
        }
        return catalog
    }()
}
