import SwiftUI
import PhotosUI
import AVKit

struct AddMomentView: View {
    @EnvironmentObject private var store: StoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var preparing = false
    @State private var message: String?
    @State private var showVideo = false
    @State private var discard = false
    @State private var importTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 24) {
                    PageTitle(kicker: "One day. One moment.",title: "Make it a memory.")
                    Text("Private on this device · \(store.group?.timezoneID ?? "")").font(.caption).foregroundStyle(PlotTheme.muted)
                    if let draft = store.state.draft {
                        ZStack(alignment: .bottomTrailing) { MediaTile(path: draft.thumbnailPath); if draft.kind == .video { Button { showVideo = true } label: { Label("Preview",systemImage: "play.fill").padding().background(.ultraThinMaterial,in: Capsule()) }.padding() } }.frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 22))
                        if draft.groupID != store.group?.id { Text("This draft belongs to another group. It will be published there.").foregroundStyle(PlotTheme.lavender) }
                        TextField("Give this moment a line…",text: Binding(get: { store.state.draft?.caption ?? "" },set: { store.state.draft?.caption = String($0.prefix(180)); store.save() }),axis: .vertical).padding(18).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 16))
                        Text("\(draft.kind == .video ? "First \(Int(draft.duration.rounded(.up))) seconds · 720p" : "Photo · up to 1920 px") · Saved draft").font(.caption).foregroundStyle(PlotTheme.muted)
                        PrimaryButton(title: "PUBLISH MOMENT",symbol: "arrow.up") { do { try store.publishDraft(); dismiss() } catch { message = error.localizedDescription } }.disabled(preparing)
                        Button("Discard draft",role: .destructive) { discard = true }
                    } else { EmptyStory(symbol: "camera.aperture",title: "Today's scene is yours.",detail: "Choose one photo or a clip. Videos are trimmed to their first 10 seconds. You can replace today's moment.") }
                    PhotosPicker(selection: $selection,matching: .any(of: [.images,.videos]),preferredItemEncoding: .current) { Label(store.state.draft == nil ? "Choose photo or video" : "Replace media",systemImage: "photo.on.rectangle.angled").font(.headline).frame(maxWidth: .infinity).padding(20).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 18)) }.disabled(preparing)
                    if preparing { HStack { ProgressView(); Text("Preparing media on your iPhone…").font(.caption) } }
                    if let message { Text(message).font(.subheadline).foregroundStyle(PlotTheme.accent) }
                    Text("Your draft stays here if you close this screen. Publishing replaces your previous moment for today. Portrait media fits the episode best.").font(.caption).foregroundStyle(PlotTheme.muted)
                }.padding(22)
            }.background(PlotTheme.background).navigationTitle("Today's moment").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.interactiveDismissDisabled(preparing)
        .onChange(of: selection) { _, item in
            guard let item, let group = store.group else { return }
            preparing = true; message = nil
            importTask = Task {
                do {
                    let draft: MomentDraft
                    if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                        guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { throw PlotError.message("Could not load this video from Photos.") }
                        draft = try await MediaService.video(movie.url,groupID: group.id)
                    } else {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw PlotError.message("Could not load this photo.") }
                        draft = try await Task.detached { try MediaService.photo(data,groupID: group.id) }.value
                    }
                    let old = store.state.draft
                    store.state.draft = draft
                    if store.save() { LocalFiles.remove(old?.mediaPath); if old?.thumbnailPath != old?.mediaPath { LocalFiles.remove(old?.thumbnailPath) } }
                    else { store.state.draft = old; LocalFiles.remove(draft.mediaPath); LocalFiles.remove(draft.thumbnailPath) }
                } catch { message = error.localizedDescription }
                preparing = false; selection = nil
            }
        }
        .confirmationDialog("Discard this saved draft?",isPresented: $discard,titleVisibility: .visible) { Button("Discard",role: .destructive) { let old = store.state.draft; store.state.draft = nil; if store.save() { LocalFiles.remove(old?.mediaPath); LocalFiles.remove(old?.thumbnailPath) } }; Button("Keep draft",role: .cancel) {} }
        .fullScreenCover(isPresented: $showVideo) { if let draft = store.state.draft { FullScreenPlayer(url: LocalFiles.url(draft.mediaPath)) } }
    }
}
struct TimelineView: View {
    @EnvironmentObject private var store: StoryStore
    @State private var weekOffset = 0
    @State private var add = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                PageTitle(kicker: "Seven days. Every perspective.",title: "The weekly cut.")
                if let g = store.group {
                    let calendar = StoryCalendar.calendar(g.timezoneID)
                    let start = calendar.date(byAdding: .weekOfYear,value: weekOffset,to: StoryCalendar.weekStart(Date(),timezone: g.timezoneID))!
                    HStack { Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").padding(12) }.accessibilityLabel("Previous week"); Spacer(); Text(StoryCalendar.dayKey(start,timezone: g.timezoneID)).font(.headline); Spacer(); Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").padding(12) }.disabled(weekOffset >= 0).accessibilityLabel("Next week") }
                    ForEach(0..<7) { index in
                        let date = calendar.date(byAdding: .day,value: index,to: start)!
                        let key = StoryCalendar.dayKey(date,timezone: g.timezoneID)
                        let moments = store.state.moments.filter { $0.groupID == g.id && $0.dayKey == key }.sorted { $0.createdAt < $1.createdAt }
                        VStack(alignment: .leading,spacing: 12) {
                            HStack { Eyebrow(text: ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][index]); Spacer(); Text(String(key.suffix(5))).font(.caption).foregroundStyle(PlotTheme.muted) }
                            if moments.isEmpty { HStack { RoundedRectangle(cornerRadius: 2).fill(PlotTheme.accent.opacity(0.4)).frame(width: 3); Text(date > Date() ? "The story hasn't happened yet." : "A quiet day in the story.").font(.caption).foregroundStyle(PlotTheme.muted); Spacer() }.frame(height: 48).padding(.horizontal,12).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 12)) }
                            else { LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())],spacing: 10) { ForEach(moments) { moment in NavigationLink { MomentDetailView(momentID: moment.id) } label: { ZStack(alignment: .bottomLeading) { MediaTile(path: moment.thumbnailPath); LinearGradient(colors: [.clear,.black.opacity(0.75)],startPoint: .center,endPoint: .bottom); HStack { Text(store.memberName(moment.userID)).font(.caption.bold()); Spacer(); if moment.mediaType == .video { Image(systemName: "play.fill") } }.padding(12) }.frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) } } }
                        }
                    }
                    if weekOffset == 0 { PrimaryButton(title: "ADD YOUR SCENE",symbol: "plus") { add = true } }
                } else { EmptyStory(symbol: "rectangle.stack",title: "Your timeline awaits.",detail: "Create a group from Home to begin.") }
            }.padding(22)
        }.background(PlotTheme.background).navigationTitle("Timeline").navigationBarTitleDisplayMode(.inline).sheet(isPresented: $add) { AddMomentView() }
    }
}
struct MomentDetailView: View {
    @EnvironmentObject private var store: StoryStore
    @Environment(\.dismiss) private var dismiss
    let momentID: String
    @State private var play = false
    @State private var delete = false
    var body: some View {
        ScrollView {
            if let m = store.state.moments.first(where: { $0.id == momentID }) {
                VStack(alignment: .leading,spacing: 24) {
                    ZStack { MediaTile(path: m.mediaType == .photo ? m.mediaPath : m.thumbnailPath); if m.mediaType == .video { Button { play = true } label: { Image(systemName: "play.circle.fill").font(.system(size: 64)).shadow(radius: 8) } } }.frame(height: 470).clipShape(RoundedRectangle(cornerRadius: 24))
                    Eyebrow(text: m.dayKey)
                    Text(store.memberName(m.userID)).font(.title.bold())
                    Text(m.caption).font(.title3)
                    HStack { ForEach(ReactionKind.allCases,id: \.self) { kind in
                        let selected = store.state.reactions.contains { $0.momentID == m.id && $0.userID == store.state.profile.id && $0.type == kind }
                        let count = store.state.reactions.filter { $0.momentID == m.id && $0.type == kind }.count
                        Button { store.toggleReaction(kind,moment: m) } label: { VStack(spacing: 6) { Image(systemName: kind.symbol); Text("\(kind.rawValue) \(count)").font(.caption2) }.frame(maxWidth: .infinity).padding(.vertical,14).background(selected ? PlotTheme.accent.opacity(0.3) : PlotTheme.surface,in: RoundedRectangle(cornerRadius: 14)) }.accessibilityLabel("\(kind.rawValue), \(count) reactions\(selected ? ", selected" : "")")
                    } }
                    if m.userID == store.state.profile.id { Button("Delete my moment",role: .destructive) { delete = true } }
                }.padding(22)
                .fullScreenCover(isPresented: $play) { FullScreenPlayer(url: LocalFiles.url(m.mediaPath)) }
                .confirmationDialog("Delete this moment? Existing copies saved to Photos cannot be recalled.",isPresented: $delete,titleVisibility: .visible) { Button("Delete moment",role: .destructive) { store.deleteMoment(m); dismiss() } }
            }
        }.background(PlotTheme.background).navigationTitle("The moment").navigationBarTitleDisplayMode(.inline)
    }
}
