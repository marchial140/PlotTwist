import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: StoryStore
    @State private var add = false
    @State private var groupForm = false
    @State private var profile = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 28) {
                HStack {
                    (Text("PLOT").fontWeight(.black) + Text("TWIST").fontWeight(.ultraLight)).font(.title2).tracking(-1)
                    Spacer()
                    Button { profile = true } label: { Avatar(name: store.state.profile.displayName,path: store.state.profile.avatarPath,size: 42) }
                }
                HStack {
                    Menu {
                        ForEach(store.state.groups) { g in Button(g.name) { store.state.selectedGroupID = g.id; store.save() } }
                        Button("Create a group",systemImage: "plus") { groupForm = true }
                    } label: { HStack { Text(store.group?.name ?? "Choose your cast").font(.subheadline.bold()); Image(systemName: "chevron.down").font(.caption) } }
                    Spacer()
                    Text(store.state.demo ? "DEMO · ON DEVICE" : "LOCAL · ON DEVICE").font(.system(size: 9,weight: .bold,design: .monospaced)).foregroundStyle(PlotTheme.muted)
                }
                if let g = store.group {
                    hero(g)
                    HStack(spacing: 0) {
                        stat("\(Set(store.weekMoments.map(\.userID)).count)/\(g.members.count)", "cast joined")
                        stat("\(store.weekMoments.count)", "moments")
                        SwiftUI.TimelineView(.periodic(from: .now,by: 60)) { context in
                            let hours = max(0, Int(StoryCalendar.weekEnd(context.date,timezone: g.timezoneID).timeIntervalSince(context.date)/3600))
                            stat(hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h", "until the finale")
                        }
                    }
                    HStack(spacing: 5) {
                        ForEach(0..<7) { day in
                            let date = StoryCalendar.calendar(g.timezoneID).date(byAdding: .day,value: day,to: StoryCalendar.weekStart(Date(),timezone: g.timezoneID))!
                            let key = StoryCalendar.dayKey(date,timezone: g.timezoneID)
                            Capsule().fill(store.weekMoments.contains(where: { $0.dayKey == key }) ? PlotTheme.accent : PlotTheme.surface).frame(height: 4)
                        }
                    }.accessibilityLabel("\(Set(store.weekMoments.map(\.dayKey)).count) days with memories")
                    PrimaryButton(title: store.state.draft == nil ? "ADD TODAY'S MOMENT" : "CONTINUE YOUR DRAFT",symbol: "plus") { add = true }
                    if let episode = store.groupEpisodes.first(where: { $0.renderedPath == nil }) {
                        NavigationLink { EpisodeEditorView(episodeID: episode.id) } label: {
                            HStack { Image(systemName: "sparkles").foregroundStyle(PlotTheme.lavender); VStack(alignment: .leading,spacing: 5) { Eyebrow(text: "Your new episode is ready to create"); Text(episode.edit.title).font(.headline) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(18).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    HStack { Eyebrow(text: "Previously on..."); Spacer(); NavigationLink("See all") { EpisodesView() }.font(.caption.bold()) }
                    if store.groupEpisodes.isEmpty { EmptyStory(symbol: "film.stack",title: "The beginning of something.",detail: "Your completed weeks will live here. Add the first memory today.") }
                    else {
                        ScrollView(.horizontal,showsIndicators: false) { HStack(spacing: 16) { ForEach(store.groupEpisodes.prefix(6)) { episode in NavigationLink { EpisodeEditorView(episodeID: episode.id) } label: { EpisodePoster(episode: episode).frame(width: 180) }.buttonStyle(.plain) } } }
                    }
                    HStack { Eyebrow(text: "The cast"); Spacer(); NavigationLink("Meet everyone") { CastView() }.font(.caption.bold()) }
                    ScrollView(.horizontal,showsIndicators: false) { HStack(spacing: 22) { ForEach(g.members) { member in NavigationLink { MemberView(member: member) } label: { VStack(spacing: 8) { Avatar(name: store.memberName(member.id)); Text(store.memberName(member.id)).font(.caption) } }.buttonStyle(.plain) } } }
                } else {
                    EmptyStory(symbol: "person.2.crop.square.stack",title: "Every story needs a cast.",detail: "Create a private local group and start collecting your week.")
                    PrimaryButton(title: "CREATE YOUR GROUP",symbol: "plus") { groupForm = true }
                    NavigationLink("Connect a shared group") { CloudConnectionView() }
                    Button("Explore a clearly labeled demo") { store.seedDemo() }.font(.subheadline)
                }
            }.padding(22).padding(.bottom,24)
        }.background(PlotTheme.background).toolbar(.hidden,for: .navigationBar)
        .sheet(isPresented: $add) { AddMomentView() }.sheet(isPresented: $groupForm) { GroupForm() }.sheet(isPresented: $profile) { ProfileView() }
    }
    private func stat(_ value: String,_ label: String) -> some View { VStack(spacing: 5) { Text(value).font(.system(.title3,design: .rounded,weight: .bold)); Text(label).font(.system(size: 10)).foregroundStyle(PlotTheme.muted) }.frame(maxWidth: .infinity) }
    private func hero(_ group: CastGroup) -> some View {
        ZStack(alignment: .bottomLeading) {
            MediaTile(path: store.weekMoments.last?.thumbnailPath ?? group.coverPath)
            LinearGradient(colors: [.clear,.black.opacity(0.2),.black.opacity(0.95)], startPoint: .top,endPoint: .bottom)
            VStack(alignment: .leading,spacing: 12) {
                HStack { Text("THIS WEEK").font(.system(size: 9,weight: .black,design: .monospaced)).tracking(2).padding(8).background(PlotTheme.accent,in: Capsule()); Spacer(); Image(systemName: "viewfinder") }; Spacer()
                Eyebrow(text: "Season 1 · Episode \(store.groupEpisodes.count + 1)")
                Text(store.weekMoments.isEmpty ? "The story\nstarts here." : "The days we'll\nremember.").font(.system(size: 38,weight: .black,design: .rounded)).tracking(-1.5)
                Text(store.currentWeekID + " · " + group.timezoneID).font(.caption).foregroundStyle(.white.opacity(0.7))
            }.padding(25)
        }.frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
struct EpisodePoster: View {
    @EnvironmentObject private var store: StoryStore
    let episode: Episode
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                MediaTile(path: store.state.moments.first { $0.id == episode.edit.coverMomentID }?.thumbnailPath)
                LinearGradient(colors: [.clear,.black.opacity(0.85)],startPoint: .center,endPoint: .bottom)
                VStack(alignment: .leading,spacing: 6) { Eyebrow(text: "S\(episode.seasonNumber) · E\(episode.episodeNumber)"); Text(episode.edit.title).font(.system(.title3,design: .rounded,weight: .black)).foregroundStyle(.white) }.padding(15)
            }.frame(height: 245).clipShape(RoundedRectangle(cornerRadius: 18))
            Text(episode.weekID).font(.caption).foregroundStyle(PlotTheme.muted)
        }
    }
}
