import SwiftUI
import AVKit

enum PlotTheme {
    static let background = Color(hex: 0x0B0B13)
    static let surface = Color(hex: 0x181824)
    static let accent = Color(hex: 0xFF654F)
    static let lavender = Color(hex: 0xA58BFF)
    static let muted = Color(hex: 0xA5A5B5)
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1) }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) { HStack { Text(title).font(.system(.subheadline, design: .rounded, weight: .heavy)); Spacer(); Image(systemName: symbol) }.padding(19).foregroundStyle(.white).background(PlotTheme.accent, in: RoundedRectangle(cornerRadius: 18)) }
            .buttonStyle(.plain)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10,weight: .heavy,design: .monospaced)).tracking(2.4).foregroundStyle(PlotTheme.lavender) }
}
struct MediaTile: View {
    var path: String?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [PlotTheme.lavender.opacity(0.5),PlotTheme.surface,PlotTheme.accent.opacity(0.5)], startPoint: .topLeading,endPoint: .bottomTrailing)
                if let image = LocalFiles.image(path) { Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width,height: proxy.size.height).clipped() }
                else { Image(systemName: "sparkles.tv").font(.system(size: 48,weight: .ultraLight)).foregroundStyle(.white.opacity(0.35)) }
            }
        }.clipped().accessibilityHidden(true)
    }
}
struct Avatar: View {
    let name: String
    var path: String? = nil
    var size: CGFloat = 50
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [PlotTheme.lavender.opacity(0.6), PlotTheme.accent.opacity(0.65)], startPoint: .topLeading,endPoint: .bottomTrailing))
            if let image = LocalFiles.image(path) { Image(uiImage: image).resizable().scaledToFill().frame(width: size,height: size).clipShape(Circle()) }
            else { Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.35,weight: .heavy,design: .rounded)) }
        }.frame(width: size,height: size).overlay(Circle().strokeBorder(.white.opacity(0.12))).accessibilityLabel(name)
    }
}
struct EmptyStory: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) { Image(systemName: symbol).font(.system(size: 42,weight: .ultraLight)).foregroundStyle(PlotTheme.accent); Text(title).font(.title2.bold()); Text(detail).font(.subheadline).foregroundStyle(PlotTheme.muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical,40).padding(.horizontal,24).background(PlotTheme.surface,in: RoundedRectangle(cornerRadius: 24))
    }
}
struct PageTitle: View {
    let kicker: String
    let title: String
    var body: some View { VStack(alignment: .leading,spacing: 8) { Eyebrow(text: kicker); Text(title).font(.system(size: 36,weight: .black,design: .rounded)).tracking(-1.5) }.frame(maxWidth: .infinity,alignment: .leading) }
}
struct FullScreenPlayer: View {
    let url: URL
    @State private var player = AVPlayer()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) { Color.black.ignoresSafeArea(); VideoPlayer(player: player).ignoresSafeArea(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).padding().background(.black.opacity(0.4),in: Circle()) }.padding() }
        .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)); player.play() }.onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }
}
