import Foundation
import FirebaseAuth
import FirebaseFirestore

struct ListingCreateRequest {
    let hostName: String
    let mushroomColor: String
    let attribute: String
    let size: String
    let location: String
    let note: String
}

enum ListingRepoError: LocalizedError {
    case notSignedIn
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You are not signed in."
        case .invalidInput(let msg):
            return msg
        }
    }
}

final class FirebaseListingsRepository {
    private let db = Firestore.firestore()

    /// Creates a listing doc in /listings
    func createListing(_ req: ListingCreateRequest) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw ListingRepoError.notSignedIn
        }

        let hostName = req.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = req.location.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !hostName.isEmpty else { throw ListingRepoError.invalidInput("Host name cannot be empty.") }
        guard hostName.count <= 30 else { throw ListingRepoError.invalidInput("Host name must be at most 30 characters.") }
        guard !location.isEmpty else { throw ListingRepoError.invalidInput("Location cannot be empty.") }

        // You can later add expiresAt if you want
        let docRef = db.collection("listings").document()

        let data: [String: Any] = [
            "hostUid": user.uid,
            "hostName": hostName,
            "mushroomColor": req.mushroomColor,
            "attribute": req.attribute,
            "size": req.size,
            "location": location,
            "note": req.note,                      // you limit it in UI already
            "joinedCount": 0,
            "maxPlayers": 10,
            "status": "open",
            "createdAt": FieldValue.serverTimestamp()
        ]

        try await docRef.setData(data)
        return docRef.documentID
    }
}
