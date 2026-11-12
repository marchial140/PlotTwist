import SwiftUI
import AVKit

struct EpisodesView: View {
    @EnvironmentObject private var store: StoryStore
    @State private var visibleCount = 12
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                PageTitle(kicker: "Your life. Available forever.",title: "The collection.")
                if store.groupEpisodes.isEmpty { EmptyStory(symbol: "film.stack",title: "Your first season is unfolding.",detail: "An episode becomes available after a week closes in your group's time zone. Open the demo from Home to try a finished week.") }
                else {
                    Text("Completed weeks · videos are generated on this iPhone.").font(.caption).foregroundStyle(PlotTheme.muted)
                    LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())],alignment: .leading,spacing: 24) {
                        ForEach(store.groupEpisodes.prefix(visibleCount)) { episode in
                            NavigationLink { EpisodeEditorView(episodeID: episode.id) } label: {
                                VStack(alignment: .leading,spacing: 8) { EpisodePoster(episode: episode); Label(available(episode.renderedPath) ? "Ready to watch" : "Ready to create",systemImage: available(episode.renderedPath) ? "play.fill" : "sparkles").font(.caption2.bold()).foregroundStyle(available(episode.renderedPath) ? PlotTheme.accent : PlotTheme.lavender); Text("\(store.state.moments.filter { $0.groupID == episode.groupID && $0.weekID == episode.weekID }.count) memories").font(.caption2).foregroundStyle(PlotTheme.muted) }
                            }.buttonStyle(.plain)
                        }
                    }
                    if visibleCount < store.groupEpisodes.count { Button("Load earlier weeks") { visibleCount += 12 }.frame(maxWidth: .infinity).padding() }
                }
            }.padding(22)
        }.background(PlotTheme.background).navigationTitle("Episodes").navigationBarTitleDisplayMode(.inline).onAppear { store.reconcileEpisodes() }
    }
    private func available(_ path: String?) -> Bool { path.map { FileManager.default.fileExists(atPath: LocalFiles.url($0).path) } ?? false }
}
struct EpisodeEditorView: View {
    @EnvironmentObject private var store: StoryStore
    let episodeID: String
    @StateObject private var renderer = EpisodeRenderer()
    @State private var edit = EpisodeEdit(title: "",orderedMomentIDs: [])
    @State private var loaded = false
    @State private var message: String?
    @State private var playURL: URL?
    @State private var shareURL: URL?
    @State private var showPlayer = false
    @State private var showShare = false
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var episode: Episode? { store.state.episodes.first { $0.id == episodeID } }
    private var sources: [Moment] { guard let episode else { return [] }; return store.state.moments.filter { $0.groupID == episode.groupID && $0.weekID == episode.weekID } }
    private var ordered: [Moment] { edit.orderedMomentIDs.compactMap { id in sources.first { $0.id == id } } }
    var body: some View {
        List {
            Section {
                PageTitle(kicker: "The director's cut",title: "Make it yours.")
                if let episode { Text("Season \(episode.seasonNumber) · Episode \(episode.episodeNumber) · \(episode.weekID)").font(.caption).foregroundStyle(PlotTheme.muted) }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section("Episode identity") {
                TextField("Episode title",text: $edit.title).onChange(of: edit.title) { _, title in if title.count > 120 { edit.title = String(title.prefix(120)) } }
                Picker("Visual style",selection: $edit.style) { ForEach(EpisodeStyle.allCases,id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Show captions",isOn: $edit.captionsEnabled)
                Toggle("Keep original clip audio",isOn: $edit.originalAudio)
                if edit.originalAudio { VStack(alignment: .leading) { Text("Clip volume · \(Int(edit.audioVolume*100))%").font(.caption); Slider(value: $edit.audioVolume,in: 0...1) } }
            }
            Section {
                ForEach(ordered) { moment in
                    HStack(spacing: 12) {
                        MediaTile(path: moment.thumbnailPath).frame(width: 48,height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading,spacing: 4) { Text(moment.caption.isEmpty ? store.memberName(moment.userID) : moment.caption).font(.subheadline).lineLimit(2); Text(moment.dayKey).font(.caption2).foregroundStyle(PlotTheme.muted) }
                        Spacer()
                        Button { if edit.excludedMomentIDs.contains(moment.id) { edit.excludedMomentIDs.remove(moment.id) } else { edit.excludedMomentIDs.insert(moment.id) } } label: { Image(systemName: edit.excludedMomentIDs.contains(moment.id) ? "circle" : "checkmark.circle.fill").foregroundStyle(PlotTheme.accent) }.buttonStyle(.borderless).accessibilityLabel(edit.excludedMomentIDs.contains(moment.id) ? "Include moment" : "Exclude moment")
                        Menu { Button("Use as cover") { edit.coverMomentID = moment.id } } label: { Image(systemName: edit.coverMomentID == moment.id ? "photo.fill" : "ellipsis.circle").foregroundStyle(PlotTheme.lavender) }.accessibilityLabel("Moment options")
                    }.opacity(edit.excludedMomentIDs.contains(moment.id) ? 0.5 : 1)
                }.onMove { source,destination in edit.orderedMomentIDs.move(fromOffsets: source,toOffset: destination) }
            } header: { Text("Scenes · \(ordered.filter { !edit.excludedMomentIDs.contains($0.id) }.count) selected") } footer: { Text("Drag the handles to reorder. Up to 24 scenes per episode. Trailers use the first six selected scenes. Missing source media must be restored or excluded.") }
            Section {
                if renderer.isRendering {
                    ProgressView(value: renderer.progress).tint(PlotTheme.accent)
                    Text(renderer.status).font(.caption.monospaced())
                    Button("Cancel generation",role: .destructive) { renderer.cancel() }
                } else {
                    PrimaryButton(title: "GENERATE EPISODE",symbol: "film") { generate(trailer: false) }
                    Button { generate(trailer: true) } label: { Label("Generate trailer",systemImage: "sparkles.tv").padding(.vertical,10) }
                }
                Text("1080 × 1920 · 30 FPS · MP4. Rendering happens on your iPhone. Keep the app open; longer exports may pause or cancel if iOS suspends it.").font(.caption).foregroundStyle(PlotTheme.muted)
            }
            if let episode {
                if let path = episode.renderedPath { outputSection("Episode",path: path) }
                if let path = episode.trailerPath { outputSection("Trailer",path: path) }
            }
            if let message { Section { Text(message).font(.subheadline).foregroundStyle(PlotTheme.lavender) } }
        }.scrollContentBackground(.hidden).background(PlotTheme.background).navigationTitle("Edit episode").navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode,.constant(.active))
        .toolbar { ToolbarItem(placement: .primaryAction) { if loaded { Image(systemName: "internaldrive").foregroundStyle(PlotTheme.muted).accessibilityLabel("Edits saved locally") } } }
        .onAppear { if !loaded, let episode { edit = episode.edit; let missing = sources.filter { !edit.orderedMomentIDs.contains($0.id) }.map(\.id); edit.orderedMomentIDs += missing; loaded = true } }
        .onChange(of: edit) { _, value in guard loaded, var episode, episode.edit != value else { return }; episode.edit = value; store.updateEpisode(episode) }
        .disabled(renderer.isRendering)
        .overlay(alignment: .bottom) {
            if renderer.isRendering { VStack(spacing: 14) { ProgressView(value: renderer.progress); Text(renderer.status).font(.caption); Button("Cancel generation",role: .destructive) { renderer.cancel() } }.padding(22).background(.ultraThinMaterial,in: RoundedRectangle(cornerRadius: 22)).padding() }
        }
        .navigationBarBackButtonHidden(renderer.isRendering)
        .interactiveDismissDisabled(renderer.isRendering)
        .fullScreenCover(isPresented: $showPlayer) { if let playURL { FullScreenPlayer(url: playURL) } }
        .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
    }
    @ViewBuilder private func outputSection(_ title: String,path: String) -> some View {
        Section(title) {
            if FileManager.default.fileExists(atPath: LocalFiles.url(path).path) {
                HStack {
                    Button { playURL = LocalFiles.url(path); showPlayer = true; if var episode { episode.watched = true; store.updateEpisode(episode,invalidate: false) } } label: { Label("Watch",systemImage: "play.fill") }.buttonStyle(.borderless)
                    Spacer()
                    Button { shareURL = LocalFiles.url(path); showShare = true } label: { Label("Share",systemImage: "square.and.arrow.up") }.buttonStyle(.borderless)
                }
                Button("Save \(title.lowercased()) to Photos") { Task { do { try await PhotoLibrary.saveVideo(LocalFiles.url(path)); message = "Saved to Photos." } catch { message = error.localizedDescription } } }
            } else { Text("The local render is missing on this device. Generate it again from your source media.").font(.caption) }
        }
    }
    private func generate(trailer: Bool) {
        guard var episode, let group = store.state.groups.first(where: { $0.id == episode.groupID }) else { return }
        episode.edit = edit
        let moments = ordered.filter { !edit.excludedMomentIDs.contains($0.id) }
        guard !moments.isEmpty else { message = "Select at least one scene."; return }
        let names = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id,store.memberName($0.id)) })
        let request = RenderRequest(groupName: group.name,timezoneID: group.timezoneID,episode: episode,moments: moments,names: names,trailer: trailer)
        message = nil
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Episode rendering") { Task { @MainActor in renderer.cancel() } }
        Task {
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid } }
            do {
                let path = try await renderer.render(request)
                guard var current = self.episode else { LocalFiles.remove(path); return }
                let old = trailer ? current.trailerPath : current.renderedPath
                if trailer { current.trailerPath = path } else { current.renderedPath = path }
                guard store.updateEpisode(current,invalidate: false) else { LocalFiles.remove(path); throw PlotError.message("The render could not be saved. Free device storage and retry.") }
                LocalFiles.remove(old)
                message = trailer ? "Your trailer is ready to watch, save or share." : "Your episode is ready to watch, save or share."
            } catch is CancellationError { message = "Generation cancelled. Your edits are saved." }
            catch { message = "Export failed: \(error.localizedDescription) Your edits are saved; retry when ready." }
        }
    }
}
