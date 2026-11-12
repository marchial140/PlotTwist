import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: StoryStore
    @State private var page = 0
    @State private var name = ""
    @State private var create = false
    @State private var join = false
    private let headlines = ["Your life\nis a story.", "Every friend\nhas a role.", "One week.\nOne episode."]
    private let descriptions = ["The little moments. The unexpected turns. A series only your friends could make.", "A private cast. Shared memories. Give your favorite people a place in the story.", "Collect your week. Create a cinematic episode on your iPhone. Keep it forever."]
    var body: some View {
        ZStack {
            PlotTheme.background.ignoresSafeArea()
            GeometryReader { p in
                Circle().fill(PlotTheme.accent.opacity(0.25)).frame(width: p.size.width).blur(radius: 80).offset(x: 100,y: 60)
                Circle().fill(PlotTheme.lavender.opacity(0.2)).frame(width: 300).blur(radius: 80).offset(x: -100,y: 350)
            }.accessibilityHidden(true)
            VStack(alignment: .leading,spacing: 24) {
                HStack { Text("PLOT").fontWeight(.black) + Text("TWIST").fontWeight(.ultraLight); Spacer(); Eyebrow(text: "Your life. Your cast.") }.padding(.top)
                Spacer(minLength: 16)
                TabView(selection: $page) {
                    ForEach(0..<3) { i in
                        VStack(alignment: .leading,spacing: 24) {
                            ZStack { RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [PlotTheme.accent.opacity(0.5), PlotTheme.lavender.opacity(0.25)],startPoint: .topLeading,endPoint: .bottomTrailing)); Image(systemName: ["viewfinder", "person.3.sequence.fill", "play.rectangle.fill"][i]).font(.system(size: 86,weight: .ultraLight)); VStack { HStack { Eyebrow(text: "PlotTwist original"); Spacer() }; Spacer(); HStack { Spacer(); Text("0\(i+1)").font(.system(size: 60,weight: .black,design: .rounded)).foregroundStyle(.white.opacity(0.3)) } }.padding(24) }.frame(height: 220)
                            Text(headlines[i]).font(.system(size: 42,weight: .black,design: .rounded)).tracking(-2).fixedSize(horizontal: false,vertical: true)
                            Text(descriptions[i]).font(.subheadline).foregroundStyle(PlotTheme.muted).lineSpacing(5)
                            Spacer(minLength: 0)
                        }.tag(i).padding(.horizontal,2)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 6) { ForEach(0..<3) { i in Capsule().fill(i == page ? PlotTheme.accent : .white.opacity(0.2)).frame(width: i == page ? 28 : 7,height: 5) } }
                if page < 2 { PrimaryButton(title: "CONTINUE") { withAnimation { page += 1 } } }
                else {
                    TextField("Your display name",text: $name).textContentType(.name).padding().background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 14))
                    PrimaryButton(title: "CREATE YOUR GROUP", symbol: "person.2.badge.plus") { store.state.profile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : String(name.prefix(40)); store.save(); create = true }
                    HStack { Button("Join a group") { join = true }; Spacer(); Button("Explore demo") { store.completeOnboarding(name: name); store.seedDemo() } }.font(.subheadline.bold())
                }
                Text("Private memories. Original stories.").font(.caption2).foregroundStyle(PlotTheme.muted).frame(maxWidth: .infinity)
            }.padding(26)
        }.sheet(isPresented: $create, onDismiss: { if !store.state.groups.isEmpty { store.completeOnboarding(name: name) } }) { GroupForm() }.sheet(isPresented: $join) { CloudConnectionView() }
    }
}
