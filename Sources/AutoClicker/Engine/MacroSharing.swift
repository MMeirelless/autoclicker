import Foundation

/// Encodes macros as `autoclicker://macro?d=…` links and `.autoclickermacro` files.
enum MacroSharing {
    static let scheme = "autoclicker"
    static let fileExtension = "autoclickermacro"

    /// A self-contained link carrying the whole macro (zlib-compressed, base64url).
    static func link(for macro: Macro) -> URL? {
        guard let json = try? Store.encoder.encode(macro) else { return nil }
        let payload = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
        let compressed = payload.count < json.count
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "macro"
        comps.queryItems = [URLQueryItem(name: "v", value: "1"),
                            URLQueryItem(name: "z", value: compressed ? "1" : "0"),
                            URLQueryItem(name: "d", value: encoded)]
        return comps.url
    }

    /// Ready-to-send message containing a short description and the link.
    static func message(for macro: Macro) -> String {
        let link = link(for: macro)?.absoluteString ?? ""
        let steps = macro.steps.count == 1 ? "1 step" : "\(macro.steps.count) steps"
        return "AutoClicker macro “\(macro.name)” (\(steps)). Open this link on a Mac with AutoClicker installed to import it:\n\(link)"
    }

    /// Decodes a link, a `.autoclickermacro` file URL, or a message containing a link.
    static func decode(url: URL) -> Macro? {
        if url.isFileURL {
            return Store.load(Macro.self, from: url)
        }
        guard url.scheme?.lowercased() == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let d = comps.queryItems?.first(where: { $0.name == "d" })?.value else { return nil }
        let compressed = comps.queryItems?.first(where: { $0.name == "z" })?.value != "0"
        var base64 = d.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard var data = Data(base64Encoded: base64) else { return nil }
        if compressed {
            guard let inflated = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
            data = inflated
        }
        return try? Store.decoder.decode(Macro.self, from: data)
    }

    /// Finds the first `autoclicker://` link inside arbitrary text (e.g. a pasted message).
    static func decode(text: String) -> Macro? {
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            if token.hasPrefix("\(scheme)://"), let url = URL(string: String(token)), let macro = decode(url: url) {
                return macro
            }
        }
        return nil
    }

    static func export(_ macro: Macro, to url: URL) throws {
        let data = try Store.encoder.encode(macro)
        try data.write(to: url, options: .atomic)
    }
}
