// Optional collaboration adapter. Local StoryStore deliberately never calls this implicitly.
// Wire an explicit cloud repository + conflict/offline UI before enabling shared groups.
#if canImport(FirebaseAuth)
import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions
import AuthenticationServices

@MainActor
final class FirebaseGateway {
    static var configured: Bool { FirebaseApp.app() != nil }
    static func configureIfPresent() {
        guard FirebaseApp.app() == nil, let path = Bundle.main.path(forResource: "GoogleService-Info",ofType: "plist"), let options = FirebaseOptions(contentsOfFile: path) else { return }
        FirebaseApp.configure(options: options)
    }
    private func requireConfigured() throws {
        guard Self.configured else { throw PlotError.message("Firebase is not configured. Local data has not been synchronized.") }
    }
    func signIn() async throws -> String {
        try requireConfigured()
        if let user = Auth.auth().currentUser { return user.uid }
        return try await Auth.auth().signInAnonymously().user.uid
    }
    /// Pass the nonce originally used in the Apple request, not its SHA256 hash.
    func linkApple(_ credential: ASAuthorizationAppleIDCredential,rawNonce: String) async throws {
        try requireConfigured()
        guard let token = credential.identityToken, let tokenString = String(data: token,encoding: .utf8), let user = Auth.auth().currentUser else { throw PlotError.message("Sign in first, then link your Apple account.") }
        let apple = OAuthProvider.appleCredential(withIDToken: tokenString,rawNonce: rawNonce,fullName: credential.fullName)
        _ = try await user.link(with: apple)
    }
    private func call(_ name: String,_ data: [String: Any]) async throws -> [String: Any] {
        try requireConfigured()
        let result = try await Functions.functions(region: "europe-west1").httpsCallable(name).call(data)
        guard let value = result.data as? [String: Any] else { throw PlotError.message("Unexpected server response.") }; return value
    }
    func createGroup(name: String,timezone: String) async throws -> String {
        _ = try await signIn()
        let result = try await call("createGroup",["name":name,"timezoneID":timezone])
        guard let id = result["groupID"] as? String else { throw PlotError.message("Missing group identifier.") }; return id
    }
    func invite(groupID: String) async throws -> String {
        let result = try await call("createInvitation",["groupID":groupID])
        guard let code = result["code"] as? String else { throw PlotError.message("Missing invitation code.") }; return code
    }
    func join(code: String) async throws -> String {
        _ = try await signIn()
        let result = try await call("joinGroup",["code":code.trimmingCharacters(in: .whitespacesAndNewlines)])
        guard let id = result["groupID"] as? String else { throw PlotError.message("Missing group identifier.") }; return id
    }
    func groups() async throws -> [QueryDocumentSnapshot] {
        let uid = try await signIn()
        return try await Firestore.firestore().collection("groups").whereField("memberIDs",arrayContains: uid).getDocuments().documents
    }
    func moments(groupID: String,weekID: String) async throws -> [QueryDocumentSnapshot] {
        try requireConfigured()
        return try await Firestore.firestore().collection("groups").document(groupID).collection("moments").whereField("weekID",isEqualTo: weekID).order(by: "createdAt").limit(to: 56).getDocuments().documents
    }
    /// Uses authenticated Storage SDK bytes, never permanent tokenized download URLs.
    func download(path: String,to localURL: URL) async throws {
        try requireConfigured()
        _ = try await Storage.storage().reference(withPath: path).writeAsync(toFile: localURL)
    }
    func uploadDraft(_ draft: MomentDraft,groupID: String,progress: @escaping (Double) -> Void) async throws {
        let uid = try await signIn()
        let ext = draft.kind == .photo ? "jpg" : "mp4"
        let path = "groups/\(groupID)/uploads/\(uid)/\(UUID().uuidString).\(ext)"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata(); metadata.contentType = draft.kind == .photo ? "image/jpeg" : "video/mp4"
        // Observer lifetime is limited to this upload; publishing only happens after Storage completes.
        let upload = ref.putFile(from: LocalFiles.url(draft.mediaPath),metadata: metadata)
        let handle = upload.observe(.progress) { snapshot in progress(snapshot.progress?.fractionCompleted ?? 0) }
        defer { upload.removeObserver(withHandle: handle) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            upload.observe(.success) { _ in continuation.resume() }
            upload.observe(.failure) { snapshot in continuation.resume(throwing: snapshot.error ?? PlotError.message("Upload failed. Your local draft is preserved.")) }
        }
        _ = try await call("publishMoment",["groupID":groupID,"mediaPath":path,"mediaType":draft.kind.rawValue,"duration":draft.duration,"caption":draft.caption])
    }
    func leave(groupID: String) async throws { _ = try await call("leaveGroup",["groupID":groupID]) }
    func deleteMoment(groupID: String,momentID: String) async throws { _ = try await call("deleteMoment",["groupID":groupID,"momentID":momentID]) }
    func deleteAccount() async throws { _ = try await call("deleteAccount",[:]) }
}
#endif
