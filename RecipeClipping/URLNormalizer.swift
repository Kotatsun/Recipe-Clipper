import Foundation

enum URLNormalizer {
    private static let droppedQueryNames: Set<String> = [
        "fbclid", "gclid", "yclid", "mc_cid", "mc_eid", "igshid", "igsh", "si"
    ]

    static func firstURL(in text: String) -> URL? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = detector.matches(in: text, range: range).first,
               let url = match.url {
                return url
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    static func normalizedURL(for text: String) -> URL? {
        guard let url = firstURL(in: text) else { return nil }
        return normalizedURL(url)
    }

    static func normalizedString(for text: String) -> String {
        normalizedURL(for: text)?.absoluteString ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.scheme == "http" || components.scheme == nil {
            components.scheme = "https"
        }
        components.host = components.host?.lowercased()
        components.fragment = nil

        if components.host?.contains("instagram.com") == true {
            let parts = components.path.split(separator: "/").map(String.init)
            if parts.count >= 2, ["p", "reel", "tv"].contains(parts[0].lowercased()) {
                components.path = "/\(parts[0])/\(parts[1])/"
            }
            components.queryItems = nil
        }

        if let items = components.queryItems {
            let kept = items
                .filter { item in
                    let name = item.name.lowercased()
                    return !name.hasPrefix("utm_") && !droppedQueryNames.contains(name)
                }
                .sorted { lhs, rhs in lhs.name == rhs.name ? (lhs.value ?? "") < (rhs.value ?? "") : lhs.name < rhs.name }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        var normalized = components.url ?? url
        let absolute = normalized.absoluteString
        if components.host?.contains("instagram.com") != true, absolute.count > 1, absolute.hasSuffix("/") {
            normalized = URL(string: String(absolute.dropLast())) ?? normalized
        }
        return normalized
    }

    static func encodedImportURL(for sharedURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "recipeclipper"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "url", value: sharedURL.absoluteString)]
        return components.url
    }

    static func importURLValue(from appURL: URL) -> String? {
        guard appURL.scheme == "recipeclipper", appURL.host == "import" else { return nil }
        return URLComponents(url: appURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value
    }
}
