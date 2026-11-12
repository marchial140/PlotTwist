import Foundation
import UIKit

enum LocalFiles {
    // Test-only override keeps XCTest libraries isolated from user data.
    static var rootOverride: URL?
    static var root: URL {
        if let rootOverride { try? FileManager.default.createDirectory(at: rootOverride, withIntermediateDirectories: true); return rootOverride }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlotTwist", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    static func newPath(_ ext: String) -> String { UUID().uuidString + "." + ext }
    static func image(_ path: String?) -> UIImage? { path.flatMap { UIImage(contentsOfFile: url($0).path) } }
    static func write(_ data: Data, extension ext: String) throws -> String {
        let path = newPath(ext)
        try data.write(to: url(path), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return path
    }
    static func remove(_ path: String?) { if let path { try? FileManager.default.removeItem(at: url(path)) } }
    static func clean(referenced: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.lastPathComponent != "state.json" && !referenced.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
        }
    }
}
