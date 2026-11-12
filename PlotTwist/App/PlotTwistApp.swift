import SwiftUI

@main
struct PlotTwistApp: App {
    @StateObject private var store = StoryStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark).tint(PlotTheme.accent)
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.reconcileEpisodes() }; if phase == .background { store.save() } }
        }
    }
}
struct RootView: View {
    @EnvironmentObject private var store: StoryStore
    var body: some View {
        Group {
            if store.storageFailed { ContentUnavailableView("Library needs recovery", systemImage: "externaldrive.badge.exclamationmark", description: Text(store.error ?? "Restore your library backup before continuing.")) }
            else if !store.state.onboardingCompleted { OnboardingView() }
            else { MainTabs() }
        }.background(PlotTheme.background)
            .alert("PlotTwist", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home",systemImage: "house.fill") }
            NavigationStack { TimelineView() }.tabItem { Label("Timeline",systemImage: "square.stack.3d.up") }
            NavigationStack { EpisodesView() }.tabItem { Label("Episodes",systemImage: "play.rectangle.fill") }
            NavigationStack { CastView() }.tabItem { Label("Cast",systemImage: "person.2.fill") }
        }.toolbarBackground(PlotTheme.surface,for: .tabBar).toolbarBackground(.visible,for: .tabBar)
    }
}
