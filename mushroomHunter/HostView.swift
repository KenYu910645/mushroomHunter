import SwiftUI
import Combine

// MARK: - Enums

enum MushroomColor: String, CaseIterable, Identifiable {
    case red = "Red"
    case yellow = "Yellow"
    case blue = "Blue"
    case purple = "Purple"
    case white = "White"
    case gray = "Gray"
    case pink = "Pink"

    var id: String { rawValue }
}

enum MushroomAttribute: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case fire = "Fire"
    case water = "Water"
    case crystal = "Crystal"
    case electric = "Electric"
    case poisonous = "Poisonous"

    var id: String { rawValue }
}

enum MushroomSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case normal = "Normal"
    case magnificent = "Magnificent"

    var id: String { rawValue }
}

// MARK: - ViewModel

@MainActor
final class HostViewModel: ObservableObject {
    // Inputs
    @Published var hostName: String = ""
    @Published var color: MushroomColor = .red
    @Published var attribute: MushroomAttribute = .normal
    @Published var size: MushroomSize = .normal
    @Published var location: String = ""
    @Published var otherMessage: String = ""

    // UI State
    @Published var showSuccessAlert: Bool = false
    @Published var successListingId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var isSubmitting: Bool = false

    // Limits
    static let hostNameMaxChars = 30
    static let otherMaxWords = 500

    private let repo = FirebaseListingsRepository()

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
        successListingId = nil

        print("🚀 submit(): start creating host room")

        defer {
            // Always stop spinner, no matter what
            isSubmitting = false
        }

        do {
            let req = ListingCreateRequest(
                hostName: hostName,
                mushroomColor: color.rawValue,
                attribute: attribute.rawValue,
                size: size.rawValue,
                location: location,
                note: otherMessage
            )

            // ⏱️ Timeout after 10 seconds
            let listingId = try await withTimeout(seconds: 10) {
                print("📡 submit(): calling repo.createListing...")
                return try await self.repo.createListing(req)
            }

            print("✅ submit(): created listing id =", listingId)

            successListingId = listingId
            showSuccessAlert = true

        } catch {
            // Full debug log
            print("❌ submit(): error =", error)

            // User-facing error
            if let le = error as? LocalizedError,
               let msg = le.errorDescription {
                errorMessage = msg
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
    
//    func submit() async {
//        guard canSubmit else { return }
//        isSubmitting = true
//        errorMessage = nil
//        successListingId = nil
//
//        do {
//            let req = ListingCreateRequest(
//                hostName: hostName,
//                mushroomColor: color.rawValue,
//                attribute: attribute.rawValue,
//                size: size.rawValue,
//                location: location,
//                note: otherMessage
//            )
//
//            let listingId = try await repo.createListing(req)
//            successListingId = listingId
//            showSuccessAlert = true
//        } catch {
//            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
//        }
//
//        isSubmitting = false
//    }

    func reset() {
        hostName = ""
        color = .red
        attribute = .normal
        size = .normal
        location = ""
        otherMessage = ""
        errorMessage = nil
        successListingId = nil
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
    @StateObject private var vm = HostViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // Host name
                Section {
                    TextField("Host name (max 30 chars)", text: $vm.hostName)
                        .onChange(of: vm.hostName) { _, _ in vm.enforceLimits() }
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    HStack {
                        Text("Remaining")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(max(vm.hostNameRemaining, 0))")
                            .foregroundColor(vm.hostNameRemaining >= 0 ? .secondary : .red)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Host Name")
                } footer: {
                    Text("Supports multiple languages. Keep it short and recognizable.")
                }

                // Mushroom properties
                Section("Mushroom") {
                    Picker("Color", selection: $vm.color) {
                        ForEach(MushroomColor.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }

                    Picker("Attribute", selection: $vm.attribute) {
                        ForEach(MushroomAttribute.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }

                    Picker("Size", selection: $vm.size) {
                        ForEach(MushroomSize.allCases) { s in
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
                    Text("Other")
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
            .navigationTitle("Host")
            .alert("Host room created!", isPresented: $vm.showSuccessAlert) {
                Button("OK") { }
                Button("Reset Form") { vm.reset() }
            } message: {
                Text("This is a prototype. Backend write will be added later.")
            }
        }
    }
}

