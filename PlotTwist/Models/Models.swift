import Foundation

struct Profile: Codable, Identifiable {
    var id = UUID().uuidString
    var displayName = "You"
    var username = "maincharacter"
    var bio = ""
    var avatarPath: String?
    var createdAt = Date()
}
struct CastMember: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var role = "THE MAIN CHARACTER"
    var joinedAt = Date()
}
struct CastGroup: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var description = ""
    var ownerID: String
    var timezoneID: String
    var createdAt = Date()
    var coverPath: String?
    var members: [CastMember]
}
enum MediaKind: String, Codable { case photo, video }
struct Moment: Codable, Identifiable, Hashable {
    var id: String
    var groupID: String
    var userID: String
    var weekID: String
    var dayKey: String
    var mediaType: MediaKind
    var mediaPath: String
    var thumbnailPath: String
    var caption: String
    var createdAt: Date
    var updatedAt: Date
    var duration: Double
}
enum ReactionKind: String, Codable, CaseIterable {
    case laugh = "Laugh", fire = "Fire", twist = "Plot twist"
    var symbol: String { switch self { case .laugh: return "face.smiling"; case .fire: return "flame"; case .twist: return "arrow.triangle.branch" } }
}
struct Reaction: Codable, Identifiable {
    var id: String { "\(momentID)_\(userID)_\(type.rawValue)" }
    var momentID: String
    var userID: String
    var type: ReactionKind
}
enum EpisodeStyle: String, Codable, CaseIterable { case cinematic = "Cinematic", comedy = "Comedy", retro = "Retro" }
struct EpisodeEdit: Codable, Equatable {
    var title: String
    var orderedMomentIDs: [String]
    var excludedMomentIDs: Set<String> = []
    var style: EpisodeStyle = .cinematic
    var captionsEnabled = true
    var originalAudio = true
    var audioVolume: Double = 0.7
    var coverMomentID: String?
}
struct Episode: Codable, Identifiable {
    var id: String
    var groupID: String
    var weekID: String
    var seasonNumber = 1
    var episodeNumber: Int
    var createdAt = Date()
    var edit: EpisodeEdit
    var renderedPath: String?
    var trailerPath: String?
    var watched = false
}
struct MomentDraft: Codable {
    var groupID: String
    var mediaPath: String
    var thumbnailPath: String
    var kind: MediaKind
    var duration: Double
    var caption = ""
    var date = Date()
}
struct AppSnapshot: Codable {
    var profile = Profile()
    var groups: [CastGroup] = []
    var moments: [Moment] = []
    var episodes: [Episode] = []
    var reactions: [Reaction] = []
    var selectedGroupID: String?
    var draft: MomentDraft?
    var onboardingCompleted = false
    var demo = false
}
