//
//  ProfileView.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme

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
    @State private var isJoinedLoading: Bool = false
    @State private var joinedErrorMessage: String? = nil
    @State private var joinedRooms: [JoinedRoomSummary] = []
    @State private var showSettingsSheet: Bool = false

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
                            Text(LocalizedStringKey("profile_name"))
                            Spacer()
                            if isEditingName {
                                TextField(LocalizedStringKey("profile_name_placeholder"), text: $draftName)
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
                            .accessibilityLabel(LocalizedStringKey("profile_edit_name_accessibility"))
                        }

                        if isEditingName {
                            Text(LocalizedStringKey("profile_name_hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button(LocalizedStringKey("common_cancel")) {
                                    draftName = session.displayName
                                    isEditingName = false
                                }

                                Spacer()

                                Button(LocalizedStringKey("common_save")) {
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
                            Text(LocalizedStringKey("profile_friend_code"))
                            Spacer()

                            if isEditingFriendCode {
                                TextField(LocalizedStringKey("profile_friend_code_placeholder"), text: $draftFriendCode)
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
                            .accessibilityLabel(LocalizedStringKey("profile_edit_friend_code_accessibility"))
                        }

                        if isEditingFriendCode {
                            Text(LocalizedStringKey("profile_friend_code_hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if let err = friendCodeError {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Button(LocalizedStringKey("common_cancel")) {
                                    draftFriendCode = session.friendCode.filter { $0.isNumber }
                                    friendCodeError = nil
                                    isEditingFriendCode = false
                                }

                                Spacer()

                                Button(LocalizedStringKey("common_save")) {
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
                    Text(LocalizedStringKey("profile_id_section"))
                }

                // MARK: - Community
                Section {
                    HStack {
                        Label(LocalizedStringKey("profile_stars"), systemImage: "star.fill")
                            .foregroundStyle(.yellow)

                        Spacer()

                        Text("\(session.stars)")
                            .font(.headline)
                            .monospacedDigit()
                    }

                    HStack {
                        Label(LocalizedStringKey("profile_honey"), systemImage: "drop.fill")
                            .foregroundStyle(.orange)

                        Spacer()

                        Text("\(session.honey)")
                            .font(.headline)
                            .monospacedDigit()
                    }

                } header: {
                    Text(LocalizedStringKey("profile_community_section"))
                } footer: {
                    Text(LocalizedStringKey("profile_community_footer"))
                }

                // MARK: - Joined Rooms
                Section {
                    if let err = joinedErrorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                    }

                    if isJoinedLoading && joinedRooms.isEmpty {
                        HStack {
                            ProgressView()
                            Text(LocalizedStringKey("profile_loading_joined"))
                                .foregroundStyle(.secondary)
                        }
                    } else if joinedRooms.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("profile_joined_empty_title"),
                            systemImage: "person.2",
                            description: Text(LocalizedStringKey("profile_joined_empty_description"))
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(joinedRooms) { r in
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
                                        Text(localizedRoomStatus(r.status))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack(spacing: 8) {
                                        Text(String(format: NSLocalizedString("profile_players_format", comment: ""), r.joinedCount, r.maxPlayers))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: NSLocalizedString("profile_bid_format", comment: ""), r.bidHoney))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text(LocalizedStringKey("profile_joined_section"))
                } footer: {
                    Text(LocalizedStringKey("profile_joined_footer"))
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
                            Text(LocalizedStringKey("profile_loading_hosted"))
                                .foregroundStyle(.secondary)
                        }
                    } else if hostedRooms.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("profile_hosted_empty_title"),
                            systemImage: "house",
                            description: Text(LocalizedStringKey("profile_hosted_empty_description"))
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(hostedRooms) { r in
                            NavigationLink {
                                RoomDetailsView(
                                    vm: RoomDetailsViewModel(roomId: r.id, session: session),
                                    onRoomClosed: {
                                        Task { await loadHostedRooms() }   // ✅ refresh list immediately
                                    }
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(r.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(localizedRoomStatus(r.status))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(String(format: NSLocalizedString("profile_players_format", comment: ""), r.joinedCount, r.maxPlayers))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(LocalizedStringKey("profile_hosted_section"))
                } footer: {
                    Text(LocalizedStringKey("profile_hosted_footer"))
                }

                // MARK: Sign out
                Section {
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Text(LocalizedStringKey("profile_sign_out"))
                    }
                } footer: {
                    Text(LocalizedStringKey("profile_footer_note"))
                }
            }
            .navigationTitle(LocalizedStringKey("profile_title"))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: scheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(LocalizedStringKey("settings_title"))
                }
            }
            .task {
                await session.refreshProfileFromBackend()
                await loadJoinedRooms()
                await loadHostedRooms()
            }
            .refreshable {
                await session.refreshProfileFromBackend()
                await loadJoinedRooms()
                await loadHostedRooms()
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                List {
                    Text(LocalizedStringKey("settings_language_managed"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle(LocalizedStringKey("settings_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showSettingsSheet = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .onAppear {
            draftName = session.displayName
            draftFriendCode = session.friendCode
            friendCodeError = nil
            Task { await session.refreshProfileFromBackend() }
        }
    }

    // MARK: - Validation / Formatting

    private func validateFriendCode(_ code: String) -> String? {
        if code.isEmpty { return NSLocalizedString("profile_friend_code_error_required", comment: "") }
        if code.count != 12 { return NSLocalizedString("profile_friend_code_error_length", comment: "") }
        if code.allSatisfy({ $0.isNumber }) == false { return NSLocalizedString("profile_friend_code_error_digits", comment: "") }
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

    private func loadJoinedRooms() async {
        guard session.isLoggedIn else { return }

        isJoinedLoading = true
        joinedErrorMessage = nil
        defer { isJoinedLoading = false }

        do {
            let rooms = try await hostRepo.fetchMyJoinedRooms(limit: 50)
            joinedRooms = rooms
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadJoinedRooms error:", error)
            joinedErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

    private func localizedRoomStatus(_ status: String) -> LocalizedStringKey {
        let lower = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "open" ? "common_open" : "common_closed"
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
