import Foundation

enum InterfaceLanguage: String, Codable, CaseIterable {
    case system, english = "en", chinese = "zh-Hans"
    var resolved: String {
        if self != .system { return rawValue }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
}

enum PreviewTheme: String, Codable, CaseIterable { case system, light, dark, paper }

struct PreviewSettings: Codable, Equatable {
    var language: InterfaceLanguage = .system
    var theme: PreviewTheme = .system
    var fontSize: Double = 17
    var wide = false
    var showOutline = true
    var highlightCode = true
    var renderMath = true
    var renderDiagrams = true

    var javascriptOptions: [String: Any] {
        ["language": language.resolved, "theme": theme.rawValue, "fontSize": min(24, max(13, fontSize)),
         "wide": wide, "showOutline": showOutline, "highlightCode": highlightCode,
         "renderMath": renderMath, "renderDiagrams": renderDiagrams]
    }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case language, theme, fontSize, wide, showOutline, highlightCode, renderMath, renderDiagrams
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = InterfaceLanguage(rawValue: try values.decodeIfPresent(String.self, forKey: .language) ?? "system") ?? .system
        theme = PreviewTheme(rawValue: try values.decodeIfPresent(String.self, forKey: .theme) ?? "system") ?? .system
        fontSize = min(24, max(13, try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 17))
        wide = try values.decodeIfPresent(Bool.self, forKey: .wide) ?? false
        showOutline = try values.decodeIfPresent(Bool.self, forKey: .showOutline) ?? true
        highlightCode = try values.decodeIfPresent(Bool.self, forKey: .highlightCode) ?? true
        renderMath = try values.decodeIfPresent(Bool.self, forKey: .renderMath) ?? true
        renderDiagrams = try values.decodeIfPresent(Bool.self, forKey: .renderDiagrams) ?? true
    }
}

/// Quick Look reads this small shared file on opening a document. No daemon or polling.
struct SettingsStore {
    static let appGroup = "DTTKLCXH53.dev.y2data.clearmark"
    let directory: URL?
    init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)) {
        self.directory = directory
    }
    func load() -> PreviewSettings {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("settings.json")),
              data.count <= 16_384, let settings = try? JSONDecoder().decode(PreviewSettings.self, from: data) else { return PreviewSettings() }
        return settings
    }
    func save(_ settings: PreviewSettings) throws {
        guard let directory else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
    }
}
