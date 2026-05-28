import Foundation

final class LocalClipBaseStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = baseURL.appendingPathComponent("ClipBase/clipbase-state.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> ClipBaseSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ClipBaseSnapshot.self, from: data)
    }

    func save(_ snapshot: ClipBaseSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
