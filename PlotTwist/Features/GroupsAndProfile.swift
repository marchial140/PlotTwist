import SwiftUI
import PhotosUI
import UserNotifications

struct GroupForm: View {
    @EnvironmentObject private var store: StoryStore
    @Environment(\.dismiss) private var dismiss
    var editing: CastGroup? = nil
    @State private var name = ""
    @State private var description = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var cover: PhotosPickerItem?
    @State private var coverPath: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            Form {
                Section("The series") { TextField("Group name",text: $name); TextField("Description (optional)",text: $description,axis: .vertical) }
                Section("Poster") {
                    if let coverPath { MediaTile(path: coverPath).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14)) }
                    PhotosPicker("Choose cover",selection: $cover,matching: .images).disabled(loading)
                    if loading { ProgressView() }
                }
                Section { Picker("Group time zone",selection: $timezone) { ForEach(TimeZone.knownTimeZoneIdentifiers,id: \.self) { Text($0).tag($0) } }.disabled(editing != nil) } footer: { Text("Fixed at creation. Daily moments and weekly closing times use this time zone, including daylight saving time.") }
                Section { Label("Local group · no server synchronization",systemImage: "iphone").font(.caption) } footer: { Text("Friends on other devices cannot join a local group. Firebase collaboration setup is documented in the project.") }
                Section {
                    PrimaryButton(title: editing == nil ? "CREATE THE CAST" : "SAVE THE CAST",symbol: "checkmark") {
                        if let editing, let i = store.state.groups.firstIndex(where: { $0.id == editing.id }) {
                            store.state.groups[i].name = String(name.prefix(60)); store.state.groups[i].description = String(description.prefix(300)); store.state.groups[i].coverPath = coverPath
                            if store.save() { dismiss() }
                        } else {
                            store.createGroup(name: name,description: description,timezone: timezone)
                            if let i = store.state.groups.firstIndex(where: { $0.id == store.group?.id }) { store.state.groups[i].coverPath = coverPath }
                            if store.save() { dismiss() }
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                }.listRowBackground(Color.clear)
            }.scrollContentBackground(.hidden).background(PlotTheme.background).navigationTitle(editing == nil ? "New series" : "Edit series").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onAppear { if let editing { name = editing.name; description = editing.description; timezone = editing.timezoneID; coverPath = editing.coverPath } }
        .onChange(of: cover) { _, item in guard let item else { return }; loading = true; Task { defer { loading = false }; do { guard let data = try await item.loadTransferable(type: Data.self) else { return }; let draft = try await Task.detached { try MediaService.photo(data,groupID: "cover") }.value; coverPath = draft.mediaPath; LocalFiles.remove(draft.thumbnailPath) } catch { store.error = error.localizedDescription } } }
    }
}
struct CastView: View {
    @EnvironmentObject private var store: StoryStore
    @State private var edit = false
    @State private var leave = false
    @State private var cloud = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                PageTitle(kicker: "No extras. All main characters.",title: "Meet the cast.")
                if let group = store.group {
                    HStack { VStack(alignment: .leading,spacing: 8) { Text(group.name).font(.title2.bold()); Text(group.description).font(.subheadline).foregroundStyle(PlotTheme.muted) }; Spacer(); Text("\(group.members.count)/8").font(.title3.monospaced().bold()).foregroundStyle(PlotTheme.accent) }
                    ForEach(group.members) { member in
                        NavigationLink { MemberView(member: member) } label: {
                            HStack(spacing: 18) { Avatar(name: store.memberName(member.id),path: member.id == store.state.profile.id ? store.state.profile.avatarPath : nil,size: 72); VStack(alignment: .leading,spacing: 8) { Eyebrow(text: member.role); Text(store.memberName(member.id)).font(.title2.bold()); Text("\(store.state.moments.filter { $0.groupID == group.id && $0.userID == member.id }.count) moments").font(.caption).foregroundStyle(PlotTheme.muted) }; Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(PlotTheme.muted) }.padding(20).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                    if group.ownerID == store.state.profile.id { PrimaryButton(title: "EDIT YOUR SERIES",symbol: "pencil") { edit = true } }
                    Button { cloud = true } label: { Label("About shared groups",systemImage: "lock.shield").frame(maxWidth: .infinity).padding() }
                    Text("Local mode · group and media stay on this iPhone. Demo characters are fictional. No invitation code is generated in local mode.").font(.caption).foregroundStyle(PlotTheme.muted)
                    Button(group.ownerID == store.state.profile.id ? "Delete local group" : "Leave group",role: .destructive) { leave = true }
                } else { EmptyStory(symbol: "person.3",title: "Casting starts with you.",detail: "Create your first group from Home.") }
            }.padding(22)
        }.background(PlotTheme.background).navigationTitle("The cast").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $edit) { GroupForm(editing: store.group) }
            .sheet(isPresented: $cloud) { CloudConnectionView() }
            .confirmationDialog("Remove this group and its local memories?",isPresented: $leave,titleVisibility: .visible) { Button("Remove group",role: .destructive) { if let group = store.group { store.leaveGroup(group) } } }
    }
}
struct MemberView: View {
    @EnvironmentObject private var store: StoryStore
    let member: CastMember
    @State private var role = ""
    private var moments: [Moment] { store.state.moments.filter { $0.groupID == store.group?.id && $0.userID == member.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 26) {
                ZStack(alignment: .bottomLeading) { MediaTile(path: moments.last?.thumbnailPath); LinearGradient(colors: [.clear,.black.opacity(0.9)],startPoint: .top,endPoint: .bottom); VStack(alignment: .leading,spacing: 14) { Eyebrow(text: "Starring"); Text(store.memberName(member.id).uppercased()).font(.system(size: 44,weight: .black,design: .rounded)); Text(member.role).font(.caption.monospaced()).tracking(2) }.padding(24) }.frame(height: 420).clipShape(RoundedRectangle(cornerRadius: 28))
                let weeks = Set(moments.map(\.weekID))
                let episodes = store.groupEpisodes.filter { weeks.contains($0.weekID) }.count
                Text("\(moments.count) moments. \(weeks.count) weeks. \(episodes) episodes.").font(.title3.bold())
                if member.id == store.state.profile.id {
                    TextField("Your character label",text: $role).padding().background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 16))
                    Button("Save my label") { if let i = store.state.groups.firstIndex(where: { $0.id == store.group?.id }), let j = store.state.groups[i].members.firstIndex(where: { $0.id == member.id }) { store.state.groups[i].members[j].role = String(role.prefix(40)); store.save() } }
                    Text("A label you choose for yourself. Nothing is inferred about your personality.").font(.caption).foregroundStyle(PlotTheme.muted)
                }
            }.padding(22)
        }.background(PlotTheme.background).navigationTitle("Character profile").navigationBarTitleDisplayMode(.inline).onAppear { role = member.role }
    }
}
struct ProfileView: View {
    @EnvironmentObject private var store: StoryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var reminders = ReminderService()
    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var avatar: PhotosPickerItem?
    @State private var hour = Date()
    @State private var deleting = false
    @State private var cloud = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Avatar(name: name,path: store.state.profile.avatarPath,size: 74); Spacer(); PhotosPicker("Change photo",selection: $avatar,matching: .images) }
                    TextField("Display name",text: $name); TextField("Username",text: $username).textInputAutocapitalization(.never).autocorrectionDisabled(); TextField("Bio",text: $bio,axis: .vertical)
                    Button("Save profile") { store.state.profile.displayName = String(name.prefix(40)); store.state.profile.username = String(username.prefix(30)); store.state.profile.bio = String(bio.prefix(180)); if store.save() { dismiss() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Your story so far") {
                    LabeledContent("Groups",value: "\(store.state.groups.count)")
                    LabeledContent("Weeks",value: "\(Set(store.state.moments.filter { $0.userID == store.state.profile.id }.map { $0.groupID + $0.weekID }).count)")
                    LabeledContent("Episodes",value: "\(store.state.episodes.filter { e in store.state.moments.contains { $0.userID == store.state.profile.id && $0.groupID == e.groupID && $0.weekID == e.weekID } }.count)")
                }
                Section("Reminders") {
                    DatePicker("Daily reminder",selection: $hour,displayedComponents: .hourAndMinute)
                    Button("Enable reminders") { let c = Calendar.current.dateComponents([.hour,.minute],from: hour); Task { await reminders.schedule(hour: c.hour ?? 20,minute: c.minute ?? 0,timezone: store.group?.timezoneID ?? TimeZone.current.identifier) } }
                    Button("Disable reminders") { reminders.disable() }
                    if let message = reminders.message { Text(message).font(.caption) }
                }
                Section("Privacy") {
                    Text("This build stores your media and profile in this iPhone's protected application storage. There are no ads, analytics, or automatic cloud uploads. Exports you save or share are separate copies.").font(.caption)
                    Button("Firebase setup & shared groups") { cloud = true }
                    Button("Delete my local account and data",role: .destructive) { deleting = true }
                }
            }.scrollContentBackground(.hidden).background(PlotTheme.background).navigationTitle("Your character").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.onAppear { name = store.state.profile.displayName; username = store.state.profile.username; bio = store.state.profile.bio }
        .onChange(of: avatar) { _, item in guard let item else { return }; Task { do { guard let data = try await item.loadTransferable(type: Data.self) else { return }; let draft = try await Task.detached { try MediaService.photo(data,groupID: "profile") }.value; let old = store.state.profile.avatarPath; store.state.profile.avatarPath = draft.mediaPath; if store.save() { LocalFiles.remove(old) }; LocalFiles.remove(draft.thumbnailPath) } catch { store.error = error.localizedDescription } } }
        .sheet(isPresented: $cloud) { CloudConnectionView() }
        .confirmationDialog("Permanently delete your local profile, groups, source media and renders? Copies in Photos or shared elsewhere remain.",isPresented: $deleting,titleVisibility: .visible) { Button("Delete all local data",role: .destructive) { reminders.disable(); store.deleteAccount(); dismiss() } }
    }
}
struct CloudConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading,spacing: 24) {
                PageTitle(kicker: "Private by design",title: "Your cast, connected.")
                Image(systemName: "lock.shield").font(.system(size: 66,weight: .ultraLight)).foregroundStyle(PlotTheme.lavender)
                Text("This version runs locally.").font(.title2.bold())
                Text("Joining friends on other iPhones requires a configured Firebase project and the deployed secure invitation backend. Local groups cannot receive remote members.").foregroundStyle(PlotTheme.muted)
                Text("The project includes Firebase authentication, private media access, security rules and transactional invitation functions. The shared-group interface and synchronization still need integration and testing before collaboration is available in this build.").foregroundStyle(PlotTheme.muted)
                Text("Developer setup: see FIREBASE.md in the project. Nothing has been uploaded.").font(.caption.monospaced()).padding(20).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 18))
            }.padding(24) }.background(PlotTheme.background).navigationTitle("Shared groups").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
