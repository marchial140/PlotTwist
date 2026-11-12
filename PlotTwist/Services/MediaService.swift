import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import UIKit

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: url)
            return ImportedMovie(url: url)
        }
    }
}
enum MediaService {
    static let maxVideoBytes = 30 * 1024 * 1024
    static func photo(_ data: Data, groupID: String) throws -> MomentDraft {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1920, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.82) else { throw PlotError.message("This photo cannot be opened.") }
        let path = try LocalFiles.write(jpeg, extension: "jpg")
        let thumb = UIImage(cgImage: cg).preparingThumbnail(of: CGSize(width: 480, height: 800)) ?? UIImage(cgImage: cg)
        let thumbnail = try LocalFiles.write(thumb.jpegData(compressionQuality: 0.7) ?? jpeg, extension: "jpg")
        return MomentDraft(groupID: groupID, mediaPath: path, thumbnailPath: thumbnail, kind: .photo, duration: 0)
    }
    static func video(_ source: URL, groupID: String) async throws -> MomentDraft {
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite && duration > 0 else { throw PlotError.message("This video has no playable frames.") }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw PlotError.message("This video format is unsupported.") }
        let path = LocalFiles.newPath("mp4")
        exporter.outputURL = LocalFiles.url(path); exporter.outputFileType = .mp4
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: min(10, duration), preferredTimescale: 600))
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()
        guard exporter.status == .completed else { LocalFiles.remove(path); throw exporter.error ?? PlotError.message("Video preparation failed.") }
        do {
            let size = (try LocalFiles.url(path).resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size <= maxVideoBytes else { throw PlotError.message("Video exceeds the 30 MB limit after compression.") }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: LocalFiles.url(path)))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 480,height: 800)
            let (cg, _) = try await generator.image(at: .zero)
            let thumbnail = try LocalFiles.write(UIImage(cgImage: cg).jpegData(compressionQuality: 0.75)!, extension: "jpg")
            return MomentDraft(groupID: groupID, mediaPath: path, thumbnailPath: thumbnail, kind: .video, duration: min(10, duration))
        } catch { LocalFiles.remove(path); throw error }
    }
}
