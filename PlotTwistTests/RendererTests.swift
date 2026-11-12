import XCTest
import AVFoundation
import UIKit
@testable import PlotTwist

@MainActor
final class RendererTests: XCTestCase {
    func testRealMP4HasVerticalVideoTrackAndFiniteDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        LocalFiles.rootOverride = directory
        defer { LocalFiles.rootOverride = nil; try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320,height: 240)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0,y: 0,width: 320,height: 240))
        }
        let path = try LocalFiles.write(image.jpegData(compressionQuality: 0.8)!,extension: "jpg")
        let moment = Moment(id:"m",groupID:"g",userID:"u",weekID:"2026-11-02",dayKey:"2026-11-02",mediaType:.photo,mediaPath:path,thumbnailPath:path,caption:"Real test",createdAt:Date(),updatedAt:Date(),duration:0)
        let episode = Episode(id:"e",groupID:"g",weekID:"2026-11-02",episodeNumber:1,edit:EpisodeEdit(title:"The test",orderedMomentIDs:["m"]))
        let renderer = EpisodeRenderer()
        let output = try await renderer.render(RenderRequest(groupName:"Cast",timezoneID:"Etc/UTC",episode:episode,moments:[moment],names:["u":"You"],trailer:true))
        let asset = AVURLAsset(url:LocalFiles.url(output))
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType:.video)
        XCTAssertEqual(tracks.count,1)
        let size = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(size.width,1080); XCTAssertEqual(size.height,1920)
        XCTAssertGreaterThan(duration,3); XCTAssertLessThan(duration,16)
        XCTAssertEqual(renderer.progress,1)
    }
    func testEmptyRenderFailsWithoutCreatingOutput() async {
        let episode = Episode(id:"e",groupID:"g",weekID:"2026-11-02",episodeNumber:1,edit:EpisodeEdit(title:"Empty",orderedMomentIDs:[]))
        do {
            _ = try await EpisodeRenderer().render(RenderRequest(groupName:"Cast",timezoneID:"Etc/UTC",episode:episode,moments:[],names:[:],trailer:false))
            XCTFail("An empty render must not succeed")
        } catch { XCTAssertFalse(error is CancellationError) }
    }
    func testCancellationTokenIsThreadSafeAndThrows() {
        let token = RenderCancellation(); token.cancel()
        XCTAssertThrowsError(try token.check()) { XCTAssertTrue($0 is CancellationError) }
    }
}
