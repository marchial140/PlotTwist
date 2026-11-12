import XCTest
@testable import PlotTwist

final class StoryTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testMondayBoundaryInGroupTimeZone() {
        XCTAssertEqual(StoryCalendar.weekID(date("2026-11-09T04:59:59Z"),timezone: "America/Toronto"),"2026-11-02")
        XCTAssertEqual(StoryCalendar.weekID(date("2026-11-09T05:00:00Z"),timezone: "America/Toronto"),"2026-11-09")
    }
    func testDaylightSavingWeekIsNotAlways168Hours() {
        let d = date("2026-03-08T12:00:00Z")
        XCTAssertEqual(StoryCalendar.weekID(d,timezone: "America/Toronto"),"2026-03-02")
        XCTAssertEqual(StoryCalendar.weekEnd(d,timezone: "America/Toronto").timeIntervalSince(StoryCalendar.weekStart(d,timezone: "America/Toronto")),167*3600)
    }
    func testYearBoundaryUsesMondayDate() {
        XCTAssertEqual(StoryCalendar.weekID(date("2027-01-01T12:00:00Z"),timezone: "Europe/Paris"),"2026-12-28")
    }
    func testStableDailyIDAndExpiredDraft() {
        XCTAssertEqual(StoryCalendar.momentID(group: "g",user: "u",day: "2026-11-12"),StoryCalendar.momentID(group: "g",user: "u",day: "2026-11-12"))
        XCTAssertFalse(StoryCalendar.canPublish(date: date("2026-11-12T12:00:00Z"),now: date("2026-11-13T12:00:00Z"),timezone: "Europe/Paris"))
    }
    private func moment(_ n: Int,user: String) -> Moment {
        Moment(id:"m\(n)",groupID:"g",userID:user,weekID:"2026-11-09",dayKey:"2026-11-09",mediaType:.photo,mediaPath:"x.jpg",thumbnailPath:"x.jpg",caption:"",createdAt:Date(timeIntervalSince1970:Double(n)),updatedAt:Date(),duration:0)
    }
    func testBalancedSelectionAndChronologicalOrder() {
        let all = (0..<30).map { moment($0,user: "a") } + (30..<37).map { moment($0,user: "b") }
        let selected = EpisodePlanner.select(all)
        XCTAssertEqual(selected.count,24)
        XCTAssertEqual(selected.filter { $0.userID == "b" }.count,7)
        XCTAssertEqual(selected.map(\.createdAt),selected.map(\.createdAt).sorted())
        XCTAssertEqual(Set(selected.map(\.id)).count,24)
    }
    func testShortVideoAndEmptySelection() {
        var m = moment(0,user: "a"); m.mediaType = .video; m.duration = 0.4
        XCTAssertEqual(EpisodePlanner.duration(for:m,trailer:false),0.4)
        XCTAssertTrue(EpisodePlanner.select([]).isEmpty)
    }
    @MainActor func testLocalPermissionsAndReplacement() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        LocalFiles.rootOverride = temporary
        defer { LocalFiles.rootOverride = nil; try? FileManager.default.removeItem(at: temporary) }
        let store = StoryStore(); store.state = AppSnapshot()
        store.createGroup(name:"Test",description:"",timezone:"Etc/UTC")
        let groupID = store.group!.id
        let path = try LocalFiles.write(Data([1,2,3]),extension:"jpg")
        store.state.draft = MomentDraft(groupID:groupID,mediaPath:path,thumbnailPath:path,kind:.photo,duration:0)
        try store.publishDraft()
        XCTAssertEqual(store.state.moments.count,1)
        store.state.draft = MomentDraft(groupID:groupID,mediaPath:path,thumbnailPath:path,kind:.photo,duration:0,caption:"Replaced")
        try store.publishDraft(); XCTAssertEqual(store.state.moments.count,1)
        var someoneElse = store.state.moments[0]; someoneElse.id = "other"; someoneElse.userID = "not-me"
        store.state.moments.append(someoneElse); store.deleteMoment(someoneElse)
        XCTAssertTrue(store.state.moments.contains { $0.id == "other" })
        store.deleteAccount()
    }
}
