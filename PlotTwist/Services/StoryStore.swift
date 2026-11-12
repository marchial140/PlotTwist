import SwiftUI
import UIKit

@MainActor
final class StoryStore: ObservableObject {
    @Published var state: AppSnapshot
    @Published var error: String?
    @Published var storageFailed = false
    var group: CastGroup? { state.groups.first { $0.id == state.selectedGroupID } ?? state.groups.first }
    var currentWeekID: String { StoryCalendar.weekID(Date(), timezone: group?.timezoneID ?? TimeZone.current.identifier) }
    var weekMoments: [Moment] { state.moments.filter { $0.groupID == group?.id && $0.weekID == currentWeekID }.sorted { $0.createdAt < $1.createdAt } }
    var groupEpisodes: [Episode] { state.episodes.filter { $0.groupID == group?.id }.sorted { $0.weekID > $1.weekID } }
    init() {
        let url = LocalFiles.url("state.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { state = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url)) }
            catch { state = AppSnapshot(); self.error = "Your saved library could not be read. It has not been overwritten. Restore state.json before continuing. \(error.localizedDescription)"; storageFailed = true }
        } else { state = AppSnapshot() }
        if !storageFailed { reconcileEpisodes(); cleanup() }
    }
    @discardableResult func save() -> Bool {
        guard !storageFailed else { return false }
        do { try JSONEncoder().encode(state).write(to: LocalFiles.url("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return true }
        catch { self.error = "Could not save your library: \(error.localizedDescription)"; return false }
    }
    func completeOnboarding(name: String) {
        state.profile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : name
        state.onboardingCompleted = true; save()
    }
    func createGroup(name: String, description: String, timezone: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let g = CastGroup(name: String(clean.prefix(60)), description: String(description.prefix(300)), ownerID: state.profile.id, timezoneID: timezone, members: [CastMember(id: state.profile.id, name: state.profile.displayName)])
        state.groups.append(g); state.selectedGroupID = g.id; save()
    }
    func publishDraft() throws {
        guard let draft = state.draft, let g = state.groups.first(where: { $0.id == draft.groupID }), g.members.contains(where: { $0.id == state.profile.id }) else { throw PlotError.message("Choose a group before publishing.") }
        guard StoryCalendar.canPublish(date: draft.date, now: Date(), timezone: g.timezoneID) else { throw PlotError.message("This draft is from an earlier day. Choose a new moment for today. Your draft is still saved.") }
        let day = StoryCalendar.dayKey(draft.date, timezone: g.timezoneID)
        let id = StoryCalendar.momentID(group: g.id, user: state.profile.id, day: day)
        let old = state.moments.first { $0.id == id }
        let snapshot = state
        state.moments.removeAll { $0.id == id }
        state.moments.append(Moment(id: id, groupID: g.id, userID: state.profile.id, weekID: StoryCalendar.weekID(draft.date, timezone: g.timezoneID), dayKey: day, mediaType: draft.kind, mediaPath: draft.mediaPath, thumbnailPath: draft.thumbnailPath, caption: String(draft.caption.prefix(180)), createdAt: old?.createdAt ?? draft.date, updatedAt: Date(), duration: draft.duration))
        state.draft = nil
        guard save() else { state = snapshot; throw PlotError.message("Publishing failed. Your draft is still available; free some storage and retry.") }
        if old?.mediaPath != draft.mediaPath { LocalFiles.remove(old?.mediaPath); LocalFiles.remove(old?.thumbnailPath) }
    }
    func deleteMoment(_ moment: Moment) {
        guard moment.userID == state.profile.id else { return }
        let snapshot = state
        state.moments.removeAll { $0.id == moment.id }; state.reactions.removeAll { $0.momentID == moment.id }
        for index in state.episodes.indices where state.episodes[index].groupID == moment.groupID && state.episodes[index].weekID == moment.weekID {
            state.episodes[index].renderedPath = nil; state.episodes[index].trailerPath = nil
        }
        guard save() else { state = snapshot; return }
        LocalFiles.remove(moment.mediaPath); LocalFiles.remove(moment.thumbnailPath)
    }
    func toggleReaction(_ kind: ReactionKind, moment: Moment) {
        guard group?.members.contains(where: { $0.id == state.profile.id }) == true else { return }
        if let i = state.reactions.firstIndex(where: { $0.momentID == moment.id && $0.userID == state.profile.id && $0.type == kind }) { state.reactions.remove(at: i) }
        else { state.reactions.append(Reaction(momentID: moment.id, userID: state.profile.id, type: kind)) }
        save()
    }
    func reconcileEpisodes(now: Date = Date()) {
        for g in state.groups {
            let weeks = Set(state.moments.filter { $0.groupID == g.id }.map(\.weekID)).sorted()
            for week in weeks {
                guard let date = StoryCalendar.date(week, timezone: g.timezoneID), StoryCalendar.weekEnd(date, timezone: g.timezoneID) <= now else { continue }
                let id = g.id + "_" + week
                guard !state.episodes.contains(where: { $0.id == id }) else { continue }
                let moments = state.moments.filter { $0.groupID == g.id && $0.weekID == week }
                let ordered = EpisodePlanner.select(moments).map(\.id)
                let number = state.episodes.filter { $0.groupID == g.id }.count + 1
                state.episodes.append(Episode(id: id, groupID: g.id, weekID: week, episodeNumber: number, edit: EpisodeEdit(title: "A week to remember", orderedMomentIDs: ordered, coverMomentID: ordered.first)))
            }
        }
        save()
    }
    @discardableResult func updateEpisode(_ episode: Episode, invalidate: Bool = true) -> Bool {
        guard let i = state.episodes.firstIndex(where: { $0.id == episode.id }) else { return false }
        let previous = state.episodes[i]
        var copy = episode
        if invalidate { copy.renderedPath = nil; copy.trailerPath = nil }
        state.episodes[i] = copy
        guard save() else { state.episodes[i] = previous; return false }
        return true
    }
    func leaveGroup(_ group: CastGroup) {
        let previous = state
        let renders = state.episodes.filter { $0.groupID == group.id }.flatMap { [$0.renderedPath, $0.trailerPath].compactMap { $0 } }
        let draftPaths = state.draft?.groupID == group.id ? [state.draft!.mediaPath, state.draft!.thumbnailPath] : []
        let ids = Set(state.moments.filter { $0.groupID == group.id }.map(\.id))
        let paths = state.moments.filter { $0.groupID == group.id }.flatMap { [$0.mediaPath, $0.thumbnailPath] }
        state.groups.removeAll { $0.id == group.id }; state.moments.removeAll { $0.groupID == group.id }
        state.episodes.removeAll { $0.groupID == group.id }; state.reactions.removeAll { ids.contains($0.momentID) }
        if state.draft?.groupID == group.id { state.draft = nil }
        state.selectedGroupID = state.groups.first?.id
        if save() { (paths + renders + draftPaths).forEach { LocalFiles.remove($0) }; LocalFiles.remove(group.coverPath) } else { state = previous }
    }
    func deleteAccount() {
        let old = state
        state = AppSnapshot()
        if save() {
            for m in old.moments { LocalFiles.remove(m.mediaPath); LocalFiles.remove(m.thumbnailPath) }
            for e in old.episodes { LocalFiles.remove(e.renderedPath); LocalFiles.remove(e.trailerPath) }
            LocalFiles.remove(old.profile.avatarPath)
            LocalFiles.remove(old.draft?.mediaPath); LocalFiles.remove(old.draft?.thumbnailPath)
        } else { state = old }
    }
    func memberName(_ id: String) -> String { id == state.profile.id ? state.profile.displayName : group?.members.first(where: { $0.id == id })?.name ?? "Former member" }
    func seedDemo() {
        guard state.groups.isEmpty else { return }
        state.demo = true; state.onboardingCompleted = true
        createGroup(name: "The Weekend Club", description: "Fictional demo cast · all memories stay on this device", timezone: TimeZone.current.identifier)
        guard let g = group else { return }
        let friends = [CastMember(id: "demo-alex", name: "Alex"), CastMember(id: "demo-jamie", name: "Jamie")]
        state.groups[0].members += friends
        let c = StoryCalendar.calendar(g.timezoneID)
        let start = StoryCalendar.weekStart(Date(), timezone: g.timezoneID)
        let captions = ["Demo · Morning light", "Demo · Take the long way", "Demo · City after hours", "Demo · Out of office", "Demo · Golden hour", "Demo · The weekend", "Demo · Until next time"]
        for offset in -7...0 {
            let day = c.date(byAdding: .day, value: offset, to: start)!
            let date = c.date(byAdding: .hour, value: 12, to: day)!
            let i = (offset + 7) % 7
            let size = CGSize(width: 720, height: 1280)
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [UIColor(red: 0.18 + Double(i) * 0.04, green: 0.12, blue: 0.34, alpha: 1).cgColor, UIColor(red: 0.95, green: 0.34 + Double(i) * 0.04, blue: 0.24, alpha: 1).cgColor]
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0,1])!
                ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 720,y: 1280), options: [])
                for n in 0..<8 { UIColor.white.withAlphaComponent(0.04).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: -120 + n*100,y: 220+n*85,width: 600,height: 600)) }
                ("PLOT\nTWIST" as NSString).draw(in: CGRect(x: 48,y: 650,width: 650,height: 300), withAttributes: [.font: UIFont.systemFont(ofSize: 112,weight: .black), .foregroundColor: UIColor.white])
                ("DEMO MEMORY 0\(i+1)" as NSString).draw(at: CGPoint(x: 52,y: 1100),withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 22,weight: .medium),.foregroundColor: UIColor.white])
            }
            guard let data = image.jpegData(compressionQuality: 0.85), let path = try? LocalFiles.write(data, extension: "jpg") else { continue }
            let user = [state.profile.id, "demo-alex", "demo-jamie"][i % 3]
            let key = StoryCalendar.dayKey(date, timezone: g.timezoneID)
            state.moments.append(Moment(id: StoryCalendar.momentID(group: g.id, user: user, day: key), groupID: g.id, userID: user, weekID: StoryCalendar.weekID(date, timezone: g.timezoneID), dayKey: key, mediaType: .photo, mediaPath: path, thumbnailPath: path, caption: captions[i], createdAt: date, updatedAt: date, duration: 0))
        }
        reconcileEpisodes(); save()
    }
    func cleanup() {
        var paths = Set(state.moments.flatMap { [$0.mediaPath, $0.thumbnailPath] })
        state.episodes.forEach { if let p = $0.renderedPath { paths.insert(p) }; if let p = $0.trailerPath { paths.insert(p) } }
        if let d = state.draft { paths.insert(d.mediaPath); paths.insert(d.thumbnailPath) }
        if let p = state.profile.avatarPath { paths.insert(p) }
        for g in state.groups { if let p = g.coverPath { paths.insert(p) } }
        LocalFiles.clean(referenced: paths)
    }
}
