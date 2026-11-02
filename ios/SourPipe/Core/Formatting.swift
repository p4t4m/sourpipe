import Foundation

public enum Format {
    public static func duration(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600
        let m = seconds / 60 % 60
        let s = seconds % 60
        let two = { (v: Int64) in v < 10 ? "0\(v)" : "\(v)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }

    /// 1234 -> 1.2K. Negative values mean "unknown" in the extractor and give nil.
    public static func compact(_ value: Int64?) -> String? {
        guard let value, value >= 0 else { return nil }
        func scaled(_ divisor: Double, _ suffix: String) -> String {
            let v = Double(value) / divisor
            let rounded = (v * 10).rounded() / 10
            let text = rounded >= 100 || rounded == rounded.rounded()
                ? String(Int(rounded.rounded())) : String(rounded)
            return text + suffix
        }
        switch value {
        case ..<1000: return String(value)
        case ..<1_000_000: return scaled(1000, "K")
        case ..<1_000_000_000: return scaled(1_000_000, "M")
        default: return scaled(1_000_000_000, "B")
        }
    }

    public static func views(_ value: Int64?) -> String? {
        compact(value).map { $0 + " views" }
    }

    /// Some services give a timestamp where others give "3 days ago"; show only its date.
    public static func date(_ text: String) -> String {
        let isTimestamp = text.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil
        return isTimestamp ? String(text.prefix(10)) : text
    }

    public static func subtitle(for item: InfoItem) -> String {
        var parts: [String] = []
        switch item.type {
        case .stream:
            if let uploader = item.uploaderName, !uploader.isEmpty { parts.append(uploader) }
            if let views = views(item.viewCount) { parts.append(views) }
            if let date = item.textualUploadDate, !date.isEmpty { parts.append(Self.date(date)) }
        case .channel:
            if let subs = compact(item.subscriberCount) { parts.append(subs + " subscribers") }
            if let count = compact(item.streamCount) { parts.append(count + " videos") }
        case .playlist:
            if let uploader = item.uploaderName, !uploader.isEmpty { parts.append(uploader) }
            if let count = compact(item.streamCount) { parts.append(count + " videos") }
        case .comment:
            break
        }
        return parts.joined(separator: " • ")
    }

    public static func kioskTitle(_ id: String) -> String {
        id.replacingOccurrences(of: "trending_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    public static func filterTitle(_ id: String) -> String {
        id.replacingOccurrences(of: "sepia_", with: "Sepia ")
            .replacingOccurrences(of: "music_", with: "Music ")
            .capitalized
    }
}
