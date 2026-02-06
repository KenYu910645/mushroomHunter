//
//  ProfileView.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore

    // Name editing
    @State private var isEditingName: Bool = false
    @State private var draftName: String = ""

    // Friend code editing
    @State private var isEditingFriendCode: Bool = false
    @State private var draftFriendCode: String = ""
    @State private var friendCodeError: String? = nil

    // host room
    @State private var isHostLoading: Bool = false
    @State private var hostErrorMessage: String? = nil
    @State private var hostedRooms: [HostedRoomSummary] = []

    private let hostRepo = FirebaseProfileHostRepository()

    // Host rooms (MVP: mock; later: load from Firestore)
    //@State private var hostedRooms: [HostedRoomStub] = []

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Account
                Section {
                    // Name row
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Name")
                            Spacer()
                            if isEditingName {
                                TextField("Pikmin in-game name", text: $draftName)
                                    .multilineTextAlignment(.trailing)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                            } else {
                                Text(session.displayName)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                if !isEditingName { isEditingName = true }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit name")
                        }

                        if isEditingName {
                            Text("Recommend to use Pikmin Bloom in-game name")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Cancel") {
                                    draftName = session.displayName
                                    isEditingName = false
                                }

                                Spacer()

                                Button("Save") {
                                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    session.updateDisplayName(trimmed)
                                    isEditingName = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // Friend code row
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Friend Code")
                            Spacer()

                            if isEditingFriendCode {
                                TextField("12 digits", text: $draftFriendCode)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .onChange(of: draftFriendCode) { _, newValue in
                                        let digitsOnly = newValue.filter { $0.isNumber }
                                        if digitsOnly != newValue {
                                            draftFriendCode = digitsOnly
                                        }
                                        if draftFriendCode.count > 12 {
                                            draftFriendCode = String(draftFriendCode.prefix(12))
                                        }
                                        friendCodeError = validateFriendCode(draftFriendCode)
                                    }
                            } else {
                                let raw = session.friendCode
                                Text(raw.isEmpty ? "XXXX XXXX XXXX" : formatFriendCode(raw))
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                if !isEditingFriendCode {
                                    isEditingFriendCode = true
                                    draftFriendCode = session.friendCode.filter { $0.isNumber }
                                    friendCodeError = validateFriendCode(draftFriendCode)
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit friend code")
                        }

                        if isEditingFriendCode {
                            Text("Copy and paste friend code in Pikmin Bloom")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if let err = friendCodeError {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Button("Cancel") {
                                    draftFriendCode = session.friendCode.filter { $0.isNumber }
                                    friendCodeError = nil
                                    isEditingFriendCode = false
                                }

                                Spacer()

                                Button("Save") {
                                    if validateFriendCode(draftFriendCode) == nil {
                                        session.updateFriendCode(draftFriendCode)
                                        isEditingFriendCode = false
                                        friendCodeError = nil
                                    } else {
                                        friendCodeError = validateFriendCode(draftFriendCode)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(validateFriendCode(draftFriendCode) != nil)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                } header: {
                    Text("ID")
                }

                // MARK: - Community
                Section {
                    HStack {
                        Label("Stars", systemImage: "star.fill")
                            .foregroundStyle(.yellow)

                        Spacer()

                        Text("\(session.stars)")
                            .font(.headline)
                            .monospacedDigit()
                    }

                    HStack {
                        Label("Honey", systemImage: "drop.fill")
                            .foregroundStyle(.orange)

                        Spacer()

                        Text("\(session.honey)")
                            .font(.headline)
                            .monospacedDigit()
                    }

                } header: {
                    Text("Community")
                } footer: {
                    Text("Stars reflect trust. Honey is your in-app balance (read-only for now).")
                }

                // MARK: - Host
                Section {
                    if let err = hostErrorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                    }

                    if isHostLoading && hostedRooms.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading hosted rooms…")
                                .foregroundStyle(.secondary)
                        }
                    } else if hostedRooms.isEmpty {
                        ContentUnavailableView(
                            "No hosted rooms",
                            systemImage: "house",
                            description: Text("Rooms you host will appear here.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(hostedRooms) { r in
                            NavigationLink {
                                RoomDetailsView(
                                    vm: RoomDetailsViewModel(roomId: r.id, session: session)
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(r.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(r.status.lowercased() == "open" ? "Open" : "Closed")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text("Players: \(r.joinedCount)/\(r.maxPlayers)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Host")
                } footer: {
                    Text("This list is loaded from Firestore: /rooms where hostUid == your uid.")
                }

                // MARK: Sign out
                Section {
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Text("Sign Out")
                    }
                } footer: {
                    Text("Profile data is local prototype for now. Later: store name + friend code in Firestore /users/{uid}.")
                }
            }
            .navigationTitle("Profile")
            .task { await loadHostedRooms() }
            .refreshable { await loadHostedRooms() }
        }
        .onAppear {
            draftName = session.displayName
            draftFriendCode = session.friendCode
            friendCodeError = nil
        }
    }

    // MARK: - Validation / Formatting

    private func validateFriendCode(_ code: String) -> String? {
        if code.isEmpty { return "Friend code is required." }
        if code.count != 12 { return "Friend code must be exactly 12 digits." }
        if code.allSatisfy({ $0.isNumber }) == false { return "Friend code must contain digits only." }
        return nil
    }

    private func loadHostedRooms() async {
        guard session.isLoggedIn else { return }

        isHostLoading = true
        hostErrorMessage = nil
        defer { isHostLoading = false }

        do {
            let rooms = try await hostRepo.fetchMyHostedRooms(limit: 50)
            hostedRooms = rooms
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadHostedRooms error:", error)
            hostErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formatFriendCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        var parts: [String] = []
        var i = digits.startIndex
        while i < digits.endIndex {
            let end = digits.index(i, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            parts.append(String(digits[i..<end]))
            i = end
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Host room stub (MVP)

private struct HostedRoomStub: Identifiable {
    let id: String
    let roomId: String
    let title: String
}

private extension ProfileView {
    static func mockHostedRooms(for name: String) -> [HostedRoomStub] {
        // Just 2 sample rooms. Replace with Firestore later.
        [
            .init(id: "h1", roomId: "room_ken_001", title: "\(name)’s Fire Hunt"),
            .init(id: "h2", roomId: "room_ken_002", title: "\(name)’s Water Squad")
        ]
    }
}
