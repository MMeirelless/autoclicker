import Foundation

/// JSON persistence in ~/Library/Application Support/AutoClicker/.
enum Store {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AutoClicker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let settingsURL = directory.appendingPathComponent("settings.json")
    static let macrosURL = directory.appendingPathComponent("macros.json")

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try decoder.decode(T.self, from: data) } catch {
            NSLog("AutoClicker: failed to decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("AutoClicker: failed to save \(url.lastPathComponent): \(error)")
        }
    }
}
