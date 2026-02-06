import SwiftUI
import Combine

// MARK: - ViewModel
import Foundation

@MainActor
final class HostViewModel: ObservableObject {
    // Dependencies
    private unowned let session: SessionStore
    private let repo: FirebaseHostRepository

    // Inputs
    @Published var hostName: String = ""
    @Published var color: MushroomColor = .Red
    @Published var attribute: MushroomAttribute = .Normal
    @Published var size: MushroomSize = .Normal
    @Published var location: String = ""
    @Published var otherMessage: String = ""

    // UI State
    @Published var showSuccessAlert: Bool = false
    @Published var successRoomId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var isSubmitting: Bool = false

    // Limits
    static let hostNameMaxChars = 30
    static let otherMaxWords = 500

    init(session: SessionStore, repo: FirebaseHostRepository = FirebaseHostRepository()) {
        self.session = session
        self.repo = repo
    }

    var hostNameRemaining: Int { Self.hostNameMaxChars - hostName.count }
    var otherWordCount: Int { Self.wordCount(otherMessage) }

    var canSubmit: Bool {
        let nameOK = !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let locOK = !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let msgOK = otherWordCount <= Self.otherMaxWords
        return nameOK && locOK && msgOK && !isSubmitting
    }

    func enforceLimits() {
        if hostName.count > Self.hostNameMaxChars {
            hostName = String(hostName.prefix(Self.hostNameMaxChars))
        }
        if otherWordCount > Self.otherMaxWords {
            otherMessage = Self.trimToWords(otherMessage, maxWords: Self.otherMaxWords)
        }
    }

    func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        errorMessage = nil
        successRoomId = nil
        showSuccessAlert = false

        print("🚀 submit(): start creating host room")

        defer { isSubmitting = false }

        do {
            let roomId = try await repo.createRoom(
                req: .init(
                    title: hostName,
                    targetColor: color.rawValue,
                    targetAttribute: attribute.rawValue,
                    targetSize: size.rawValue,
                    location: location,
                    note: otherMessage
                ),
                hostName: session.displayName,
                hostStars: session.stars
            )

            print("✅ submit(): created room id =", roomId)
            successRoomId = roomId
            showSuccessAlert = true

        } catch {
            print("❌ submit(): error =", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reset() {
        hostName = ""
        color = .Red
        attribute = .Normal
        size = .Normal
        location = ""
        otherMessage = ""
        errorMessage = nil
        successRoomId = nil
        showSuccessAlert = false
    }

    // MARK: Word utils
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func trimToWords(_ text: String, maxWords: Int) -> String {
        let comps = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        if comps.count <= maxWords { return text }
        return comps.prefix(maxWords).joined(separator: " ")
    }
}

// MARK: - View

struct HostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm: HostViewModel

    init(vm: HostViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Host name
                Section {
                    TextField("Ex: Let's fight mushroom", text: $vm.hostName)
                        .onChange(of: vm.hostName) { _, _ in vm.enforceLimits() }
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

//                    HStack {
//                        Text("Remaining")
//                            .foregroundStyle(.secondary)
//                        Spacer()
//                        Text("\(max(vm.hostNameRemaining, 0))")
//                            .foregroundColor(vm.hostNameRemaining >= 0 ? .secondary : .red)
//                            .monospacedDigit()
//                    }
                } header: {
                    Text("Room Name")
                } footer: {
                    Text("Supports multiple languages. Keep it short and recognizable.")
                }

                // Mushroom properties
                Section("Target Mushroom") {
                    Picker("Color", selection: $vm.color) {
                        ForEach(MushroomColor.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }

                    Picker("Attribute", selection: $vm.attribute) {
                        ForEach(MushroomAttribute.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }

                    Picker("Size", selection: $vm.size) {
                        ForEach(MushroomSize.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }

                // Location
                Section {
                    TextField("Country / City / Suburb / Area", text: $vm.location)
                        .onChange(of: vm.location) { _, _ in
                            // Optional: you can add a char limit here too if you want.
                        }
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Location")
                } footer: {
                    Text("Type a rough location. Avoid full addresses for privacy.")
                }

                // Other message (500 words max)
                Section {
                    TextEditor(text: $vm.otherMessage)
                        .frame(minHeight: 140)
                        .onChange(of: vm.otherMessage) { _, _ in vm.enforceLimits() }

                    HStack {
                        Text("Words")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(vm.otherWordCount)/\(HostViewModel.otherMaxWords)")
                            .foregroundColor(vm.otherWordCount <= HostViewModel.otherMaxWords ? .secondary : .red)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Room Description")
                } footer: {
                    Text("Max 500 words. Use it for extra notes like time window, expectations, or friend code.")
                }

                // Error
                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }

                // Create button
                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Create Host Room").font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!vm.canSubmit)
                }
            }
            .navigationTitle("Create Room")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .alert("Host room created!", isPresented: $vm.showSuccessAlert) {
                Button("OK") { }
                Button("Reset Form") { vm.reset() }
            } message: {
                Text("This is a prototype. Backend write will be added later.")
            }
        }
    }
}

