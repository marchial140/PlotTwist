import AVFoundation
import UIKit
import CoreVideo

final class RenderCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func check() throws { if cancelled { throw CancellationError() } }
}
struct RenderRequest {
    let groupName: String
    let timezoneID: String
    let episode: Episode
    let moments: [Moment]
    let names: [String: String]
    let trailer: Bool
}
private struct RenderSegment {
    let moment: Moment?
    let start: Double
    let duration: Double
    let ending: Bool
}
@MainActor
final class EpisodeRenderer: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRendering = false
    @Published private(set) var status = ""
    private var cancellation: RenderCancellation?
    func cancel() { cancellation?.cancel(); status = "Cancelling…" }
    func render(_ request: RenderRequest) async throws -> String {
        guard !isRendering else { throw PlotError.message("An export is already running.") }
        let token = RenderCancellation(); cancellation = token; isRendering = true; progress = 0; status = "Rendering frames…"
        defer { isRendering = false; cancellation = nil }
        let path: String = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.write(request,token: token) { value, label in
                        Task { @MainActor in self.progress = value; self.status = label }
                    }
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
        progress = 1; status = "Your video is ready."
        return path
    }
    private nonisolated static func plan(_ request: RenderRequest) -> [RenderSegment] {
        let count = request.trailer ? min(6,request.moments.count) : min(24,request.moments.count)
        let moments = Array(request.moments.prefix(count))
        var segments = [RenderSegment(moment: nil,start: 0,duration: request.trailer ? 1 : 3,ending: false)]
        var cursor = segments[0].duration
        for moment in moments {
            let duration = min(EpisodePlanner.duration(for: moment,trailer: request.trailer),request.trailer ? 1.8 : 69 / Double(max(1,count)))
            segments.append(RenderSegment(moment: moment,start: cursor,duration: duration,ending: false)); cursor += duration
        }
        segments.append(RenderSegment(moment: nil,start: cursor,duration: request.trailer ? 2 : 3,ending: true))
        return segments
    }
    private nonisolated static func write(_ request: RenderRequest, token: RenderCancellation, progress: @escaping @Sendable (Double,String) -> Void) throws -> String {
        guard !request.moments.isEmpty else { throw PlotError.message("Choose at least one available moment.") }
        let segments = plan(request)
        let total = segments.last!.start + segments.last!.duration
        let frames = Int(ceil(total * 30))
        let path = LocalFiles.newPath("mp4")
        let raw = LocalFiles.url(path)
        var success = false
        defer { if !success { LocalFiles.remove(path) } }
        let writer = try AVAssetWriter(outputURL: raw,fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video,outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,AVVideoWidthKey: 1080,AVVideoHeightKey: 1920,AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,AVVideoExpectedSourceFrameRateKey: 30,AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String: 1080,kCVPixelBufferHeightKey as String: 1920,kCVPixelBufferCGImageCompatibilityKey as String: true,kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw PlotError.message("This device cannot encode the requested video.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? PlotError.message("Cannot start video export.") }
        writer.startSession(atSourceTime: .zero)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        var segmentIndex = -1
        var still: UIImage?
        var generator: AVAssetImageGenerator?
        for frame in 0..<frames {
            try token.check()
            while !input.isReadyForMoreMediaData {
                try token.check()
                guard writer.status == .writing else { throw writer.error ?? PlotError.message("Video encoder stopped.") }
                Thread.sleep(forTimeInterval: 0.003)
            }
            try autoreleasepool {
                let seconds = Double(frame)/30
                let index = segments.lastIndex(where: { $0.start <= seconds }) ?? 0
                let segment = segments[index]
                if index != segmentIndex {
                    still = nil; generator = nil; segmentIndex = index
                    if let moment = segment.moment {
                        let url = LocalFiles.url(moment.mediaPath)
                        guard FileManager.default.fileExists(atPath: url.path) else { throw PlotError.message("A source file is missing. Restore it or exclude the moment.") }
                        if moment.mediaType == .photo {
                            guard let image = UIImage(contentsOfFile: url.path) else { throw PlotError.message("A photo could not be decoded.") }; still = image
                        } else {
                            let g = AVAssetImageGenerator(asset: AVURLAsset(url: url)); g.appliesPreferredTrackTransform = true
                            g.maximumSize = CGSize(width: 1080,height: 1920)
                            g.requestedTimeToleranceBefore = CMTime(value: 1,timescale: 30); g.requestedTimeToleranceAfter = CMTime(value: 1,timescale: 30)
                            generator = g
                        }
                    }
                }
                let elapsed = seconds - segment.start
                var image = still
                if let generator, let moment = segment.moment {
                    let sample = min(elapsed,max(0,moment.duration - 0.05))
                    let cg = try generator.copyCGImage(at: CMTime(seconds: sample,preferredTimescale: 600),actualTime: nil)
                    image = UIImage(cgImage: cg)
                }
                guard let pool = adaptor.pixelBufferPool else { throw PlotError.message("Cannot allocate a video frame.") }
                var pixelBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixelBuffer) == kCVReturnSuccess, let buffer = pixelBuffer else { throw PlotError.message("Not enough memory for video rendering.") }
                CVPixelBufferLockBaseAddress(buffer,[])
                defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),width: 1080,height: 1920,bitsPerComponent: 8,bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw PlotError.message("Cannot create the rendering surface.") }
                context.translateBy(x: 0,y: 1920); context.scaleBy(x: 1,y: -1)
                UIGraphicsPushContext(context); defer { UIGraphicsPopContext() }
                draw(request: request,segment: segment,image: image,elapsed: elapsed,context: context)
                guard adaptor.append(buffer,withPresentationTime: CMTime(value: Int64(frame),timescale: 30)) else { throw writer.error ?? PlotError.message("Could not write a frame.") }
            }
            if frame % 10 == 0 { progress(Double(frame)/Double(frames)*0.85,"Rendering frame \(frame + 1) of \(frames)…") }
        }
        input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: Int64(frames),timescale: 30))
        let finished = DispatchSemaphore(value: 0); writer.finishWriting { finished.signal() }; finished.wait()
        try token.check()
        guard writer.status == .completed else { throw writer.error ?? PlotError.message("Video export did not complete.") }
        if request.episode.edit.originalAudio && request.moments.contains(where: { $0.mediaType == .video }) {
            let mixed = try mixAudio(raw,request: request,segments: segments,token: token,progress: progress)
            LocalFiles.remove(path); success = true; return mixed
        }
        success = true; progress(1,"Video ready"); return path
    }
    private nonisolated static func draw(request: RenderRequest,segment: RenderSegment,image: UIImage?,elapsed: Double,context: CGContext) {
        let canvas = CGRect(x: 0,y: 0,width: 1080,height: 1920)
        let style = request.episode.edit.style
        let background = style == .retro ? UIColor(red: 0.15,green: 0.12,blue: 0.09,alpha: 1) : UIColor(red: 0.043,green: 0.043,blue: 0.075,alpha: 1)
        background.setFill(); context.fill(canvas)
        let accent = style == .comedy ? UIColor(red: 0.73,green: 0.98,blue: 0.33,alpha: 1) : style == .retro ? UIColor(red: 1,green: 0.81,blue: 0.48,alpha: 1) : UIColor(red: 1,green: 0.40,blue: 0.31,alpha: 1)
        let font: (CGFloat,UIFont.Weight) -> UIFont = { size,weight in style == .retro ? UIFont.monospacedSystemFont(ofSize: size,weight: weight) : UIFont.systemFont(ofSize: size,weight: weight) }
        func text(_ value: String, y: CGFloat,size: CGFloat,color: UIColor = .white,center: Bool = false) {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = center ? .center : .left
            (value as NSString).draw(in: CGRect(x: 78,y: y,width: 924,height: 360),withAttributes: [.font: font(size,.heavy),.foregroundColor: color,.paragraphStyle: paragraph])
        }
        if let image, let moment = segment.moment {
            let zoom: CGFloat = moment.mediaType == .photo ? 1 + 0.045 * CGFloat(elapsed/segment.duration) : 1
            let scale = max(1080/image.size.width,1920/image.size.height)*zoom
            let size = CGSize(width: image.size.width*scale,height: image.size.height*scale)
            image.draw(in: CGRect(x: (1080-size.width)/2,y: (1920-size.height)/2,width: size.width,height: size.height))
            let colors = [UIColor.clear.cgColor,UIColor.black.withAlphaComponent(0.8).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors: colors,locations: [0,1]) { context.drawLinearGradient(gradient,start: CGPoint(x: 0,y: 950),end: CGPoint(x: 0,y: 1920),options: []) }
            if style == .retro { UIColor(red: 0.9,green: 0.6,blue: 0.2,alpha: 0.12).setFill(); context.fill(canvas); accent.setStroke(); context.setLineWidth(4); context.stroke(canvas.insetBy(dx: 36,dy: 36)); text("REC  •  \(moment.dayKey)",y: 90,size: 28,color: accent) }
            else {
                let day = StoryCalendar.date(moment.dayKey,timezone: request.timezoneID) ?? moment.createdAt
                let weekday = StoryCalendar.calendar(request.timezoneID).component(.weekday,from: day)
                let act = (weekday == 1 || weekday == 7) ? "ACT III · THE WEEKEND" : weekday <= 4 ? "ACT I · THE WEEK BEGINS" : "ACT II · THINGS GET INTERESTING"
                text(act,y: 100,size: 23,color: accent)
            }
            text(request.names[moment.userID] ?? "THE CAST",y: 1440,size: 36,color: accent)
            if request.episode.edit.captionsEnabled { text(moment.caption,y: 1515,size: 54) }
            text(moment.dayKey,y: 1770,size: 25)
        } else if segment.ending {
            text(request.trailer ? "WHAT HAPPENED\nTHIS WEEK?" : "TO BE\nCONTINUED…",y: 650,size: 94,center: true)
            text(request.trailer ? "WATCH YOUR LIFE UNFOLD." : "NEXT EPISODE — NEXT WEEK",y: 1150,size: 30,color: accent,center: true)
            text("PLOTTWIST",y: 1500,size: 35,center: true)
        } else {
            accent.setFill(); context.fill(CGRect(x: 78,y: 530,width: 100,height: 8))
            text("PLOTTWIST ORIGINAL",y: 590,size: 26,color: accent)
            text(request.groupName.uppercased(),y: 700,size: 86)
            text(request.episode.edit.title,y: 1040,size: 50)
            text("SEASON \(request.episode.seasonNumber)  /  EPISODE \(request.episode.episodeNumber)",y: 1360,size: 26,color: accent)
        }
        // Each cut fades through black; no stretching, paid music or fabricated footage.
        let fade = min(1,min(elapsed/0.22,(segment.duration-elapsed)/0.22))
        UIColor.black.withAlphaComponent(CGFloat(max(0,1-fade))).setFill(); context.fill(canvas)
        ("PLOTTWIST" as NSString).draw(at: CGPoint(x: 820,y: 1845),withAttributes: [.font: UIFont.systemFont(ofSize: 18,weight: .bold),.foregroundColor: UIColor.white.withAlphaComponent(0.6)])
    }
    private nonisolated static func mixAudio(_ raw: URL,request: RenderRequest,segments: [RenderSegment],token: RenderCancellation,progress: @escaping @Sendable (Double,String) -> Void) throws -> String {
        let composition = AVMutableComposition()
        let source = AVURLAsset(url: raw)
        guard let sourceVideo = source.tracks(withMediaType: .video).first, let video = composition.addMutableTrack(withMediaType: .video,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw PlotError.message("Cannot reopen the rendered video.") }
        try video.insertTimeRange(CMTimeRange(start: .zero,duration: source.duration),of: sourceVideo,at: .zero)
        var parameters: [AVAudioMixInputParameters] = []
        for segment in segments {
            try token.check()
            guard let moment = segment.moment, moment.mediaType == .video else { continue }
            let asset = AVURLAsset(url: LocalFiles.url(moment.mediaPath))
            guard let original = asset.tracks(withMediaType: .audio).first, let audio = composition.addMutableTrack(withMediaType: .audio,preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let range = CMTimeRange(start: .zero,duration: CMTime(seconds: min(segment.duration,asset.duration.seconds),preferredTimescale: 600))
            try audio.insertTimeRange(range,of: original,at: CMTime(seconds: segment.start,preferredTimescale: 600))
            let parameter = AVMutableAudioMixInputParameters(track: audio); parameter.setVolume(Float(request.episode.edit.audioVolume),at: .zero); parameters.append(parameter)
        }
        let mix = AVMutableAudioMix(); mix.inputParameters = parameters
        guard let export = AVAssetExportSession(asset: composition,presetName: AVAssetExportPresetHighestQuality) else { throw PlotError.message("Cannot assemble original audio.") }
        let path = LocalFiles.newPath("mp4"); export.outputURL = LocalFiles.url(path); export.outputFileType = .mp4; export.audioMix = mix; export.shouldOptimizeForNetworkUse = true
        let done = DispatchSemaphore(value: 0); export.exportAsynchronously { done.signal() }
        while done.wait(timeout: .now() + 0.1) == .timedOut {
            if token.cancelled { export.cancelExport(); done.wait(); LocalFiles.remove(path); throw CancellationError() }
            progress(0.85 + Double(export.progress)*0.14,"Mixing original audio…")
        }
        guard export.status == .completed else { LocalFiles.remove(path); throw export.error ?? PlotError.message("Audio export failed.") }
        return path
    }
}
