import Foundation

/// App-owned interface copy. Keep backend evidence, error details, model names, and user content untouched.
enum L10n {
    private static let englishBundle: Bundle = {
        guard let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .module }
        return bundle
    }()

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, bundle: .module, arguments: arguments)
    }

    /// Explicit-language lookup keeps localization behavior testable and falls back to the package's English table.
    static func tr(_ key: String, language: String?, arguments: [CVarArg] = []) -> String {
        let bundle = language.map { resourceBundle(for: $0) ?? englishBundle } ?? .module
        return format(key, bundle: bundle, arguments: arguments)
    }

    private static func resourceBundle(for language: String) -> Bundle? {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private static func format(_ key: String, bundle: Bundle, arguments: [CVarArg]) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        let englishFormat = format == key
            ? englishBundle.localizedString(forKey: key, value: key, table: "Localizable")
            : format
        guard !arguments.isEmpty else { return englishFormat }
        let locale = Locale(identifier: bundle.preferredLocalizations.first ?? Locale.current.identifier)
        return String(format: englishFormat, locale: locale, arguments: arguments)
    }

    /// The CLI's compact age strings are display metadata, not evidence. Translate known forms and preserve unknown ones.
    static func ago(_ value: String?) -> String? {
        localizedAgo(value, language: nil)
    }

    static func localizedAgo(_ value: String?, language: String?) -> String? {
        guard let value, !value.isEmpty else { return value }
        let pattern = #"^(\d+)([smhd]) ago$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let countRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value) else { return value }
        let count = String(value[countRange])
        let key: String
        switch value[unitRange] {
        case "s": key = "%@s ago"
        case "m": key = "%@m ago"
        case "h": key = "%@h ago"
        case "d": key = "%@d ago"
        default: return value
        }
        return tr(key, language: language, arguments: [count])
    }

    /// Translate only known CLI summary components; an unknown component keeps the complete original message.
    static func statusMessage(_ message: String, language: String? = nil) -> String {
        let components = message.components(separatedBy: " · ")
        let translated = components.compactMap { statusComponent($0, language: language) }
        guard translated.count == components.count else { return message }
        return translated.joined(separator: " · ")
    }

    private static func statusComponent(_ value: String, language: String?) -> String? {
        switch value {
        case "fresh session downgraded", "all clear", "no active threads":
            return tr(value, language: language)
        default:
            break
        }

        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, Int(parts[0]) != nil else { return nil }
        let count = parts[0]
        switch parts[1] {
        case "downgraded": return tr("%@ downgraded", language: language, arguments: [count])
        case "suspicious": return tr("%@ suspicious", language: language, arguments: [count])
        case "upgraded": return tr("%@ upgraded", language: language, arguments: [count])
        case "unverified": return tr("%@ unverified", language: language, arguments: [count])
        case "probe running": return tr("%@ probe running", language: language, arguments: [count])
        case "probes running": return tr("%@ probes running", language: language, arguments: [count])
        default: return nil
        }
    }

    static func evidenceText(_ text: String, ago: String?, active: Bool, language: String? = nil) -> String {
        var result = text
        if let ago = localizedAgo(ago, language: language), !ago.isEmpty { result += " · \(ago)" }
        if !active { result += " · \(tr("reverted", language: language))" }
        return result
    }
}
