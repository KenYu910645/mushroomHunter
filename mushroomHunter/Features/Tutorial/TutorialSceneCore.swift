//
//  TutorialSceneCore.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines shared tutorial-scene primitives and cross-scenario helpers.
//
//  Defined in this file:
//  - TutorialScene shared models used by all six tutorial scenarios.
//
import Foundation

/// Centralized tutorial scene entry point used by interactive tutorials.
enum TutorialScene {
    /// Supported tutorial copy locales stored in this config file.
    enum Language {
        case en /// English
        case cn /// Traditional Chinese
    }

    /// One line-by-line bilingual text entry.
    struct BilingualText {
        let en: String /// English
        let cn: String /// Traditional Chinese

        /// Resolves text for selected language.
        /// - Parameter language: Current tutorial language.
        /// - Returns: Localized text for that language.
        func value(for language: Language) -> String {
            switch language {
            case .en:
                return en
            case .cn:
                return cn
            }
        }
    }

    /// Shared tutorial step model used by all interactive tutorial scenes.
    /// Stores bilingual copy and resolves display strings lazily for current language.
    struct Step {
        /// Optional live highlight target resolved from anchored UI elements.
        let highlightTarget: TutorialHighlightTarget?
        /// Bilingual step title.
        private let titleText: BilingualText
        /// Bilingual step description.
        private let messageText: BilingualText

        /// Creates one step from bilingual content plus optional live highlight target.
        /// - Parameters:
        ///   - highlightTarget: Optional live highlight target.
        ///   - title: Bilingual step title.
        ///   - message: Bilingual step description.
        init(
            highlightTarget: TutorialHighlightTarget?,
            title: BilingualText,
            message: BilingualText
        ) {
            self.highlightTarget = highlightTarget
            self.titleText = title
            self.messageText = message
        }

        /// Step card title text localized for current language.
        var title: String {
            titleText.value(for: TutorialScene.currentLanguage)
        }

        /// Step card description text localized for current language.
        var message: String {
            messageText.value(for: TutorialScene.currentLanguage)
        }
    }

    /// Returns tutorial language based on current preferred system language.
    static var currentLanguage: Language {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        let isTraditionalChinese = preferredLanguage.contains("zh-hant")
            || preferredLanguage.contains("zh-tw")
            || preferredLanguage.contains("zh-hk")
        return isTraditionalChinese ? .cn : .en
    }

    /// Resolves bundled tutorial postcard snapshot asset name for a listing id.
    /// - Parameter listingId: Postcard listing identifier shown in tutorial scenes.
    /// - Returns: Asset name when the listing belongs to tutorial fake data; otherwise nil.
    static func tutorialPostcardSnapshotAssetName(for listingId: String) -> String? {
        switch listingId {
        case PostcardBrowse.replayPostcardId:
            return "TutorialPostcardSnapshotBaby"
        case "tutorial-postcard-ordered":
            return "TutorialPostcardSnapshotHippo"
        case "tutorial-postcard-general-1":
            return "TutorialPostcardSnapshotHugePikmin"
        case "tutorial-postcard-general-2":
            return "TutorialPostcardSnapshotDuck"
        case PostcardBuyer.replayPostcardId, PostcardSeller.replayPostcardId:
            return "TutorialPostcardSnapshotDuck"
        default:
            return nil
        }
    }

    /// Builds one localized postcard listing for tutorial detail scenes.
    /// - Parameters:
    ///   - id: Stable tutorial listing id.
    ///   - sellerId: Fake seller uid.
    ///   - title: Bilingual listing title.
    ///   - priceHoney: Honey price shown in detail.
    ///   - country: Bilingual country label.
    ///   - province: Bilingual province/city label.
    ///   - detail: Bilingual location detail label.
    ///   - sellerName: Bilingual seller display name.
    ///   - sellerFriendCode: Seller friend code shown in detail.
    ///   - stock: Fake stock count.
    ///   - createdAtOffsetSeconds: Relative seconds before now for `createdAt`.
    /// - Returns: Localized postcard listing ready for tutorial presentation.
    static func makeTutorialPostcardDetailListing(
        id: String,
        sellerId: String,
        title: BilingualText,
        priceHoney: Int,
        country: BilingualText,
        province: BilingualText,
        detail: BilingualText,
        sellerName: BilingualText,
        sellerFriendCode: String,
        stock: Int,
        createdAtOffsetSeconds: TimeInterval
    ) -> PostcardListing {
        let language = currentLanguage
        return PostcardListing(
            id: id,
            sellerId: sellerId,
            title: title.value(for: language),
            priceHoney: priceHoney,
            location: PostcardLocation(
                country: country.value(for: language),
                province: province.value(for: language),
                detail: detail.value(for: language)
            ),
            sellerName: sellerName.value(for: language),
            sellerFriendCode: sellerFriendCode,
            stock: stock,
            imageUrl: nil,
            thumbnailUrl: nil,
            createdAt: Date().addingTimeInterval(createdAtOffsetSeconds)
        )
    }

    /// Shared fake room model used by browse-list tutorial scenes.
    /// Stores bilingual fields and resolves display strings lazily for current language.
    struct BrowseFakeRoom {
        /// Stable room id used by list and ownership tagging.
        let id: String
        /// Bilingual room title.
        private let titleText: BilingualText
        /// Bilingual mushroom type text.
        private let mushroomTypeText: BilingualText
        /// Fake joined attendee count.
        let joinedPlayers: Int
        /// Fake room attendee cap.
        let maxPlayers: Int
        /// Fake host uid for room model shape.
        let hostUid: String
        /// Fake host stars used by sorting.
        let hostStars: Int
        /// Bilingual location text rendered in browse row.
        private let locationText: BilingualText
        /// Relative seconds before now for `createdAt`.
        let createdAtOffsetSeconds: TimeInterval
        /// Relative seconds before now for `lastSuccessfulRaidAt`.
        let lastSuccessfulRaidAtOffsetSeconds: TimeInterval

        /// Creates one fake browse-room payload with bilingual text fields.
        /// - Parameters:
        ///   - id: Stable room id.
        ///   - title: Bilingual room title.
        ///   - mushroomType: Bilingual mushroom type.
        ///   - joinedPlayers: Joined attendee count.
        ///   - maxPlayers: Max attendee count.
        ///   - hostUid: Host uid for model shape.
        ///   - hostStars: Host stars.
        ///   - location: Bilingual location text.
        ///   - createdAtOffsetSeconds: Created-at offset from now.
        ///   - lastSuccessfulRaidAtOffsetSeconds: Last-raid offset from now.
        init(
            id: String,
            title: BilingualText,
            mushroomType: BilingualText,
            joinedPlayers: Int,
            maxPlayers: Int,
            hostUid: String,
            hostStars: Int,
            location: BilingualText,
            createdAtOffsetSeconds: TimeInterval,
            lastSuccessfulRaidAtOffsetSeconds: TimeInterval
        ) {
            self.id = id
            self.titleText = title
            self.mushroomTypeText = mushroomType
            self.joinedPlayers = joinedPlayers
            self.maxPlayers = maxPlayers
            self.hostUid = hostUid
            self.hostStars = hostStars
            self.locationText = location
            self.createdAtOffsetSeconds = createdAtOffsetSeconds
            self.lastSuccessfulRaidAtOffsetSeconds = lastSuccessfulRaidAtOffsetSeconds
        }

        /// Fake room title localized for current language.
        var title: String {
            titleText.value(for: TutorialScene.currentLanguage)
        }

        /// Fake mushroom type localized for current language.
        var mushroomType: String {
            mushroomTypeText.value(for: TutorialScene.currentLanguage)
        }

        /// Fake location localized for current language.
        var location: String {
            locationText.value(for: TutorialScene.currentLanguage)
        }
    }

    /// Shared room-detail tutorial configuration primitives.
    enum RoomDetailTutorial {
        /// Shared step shape alias used by room-detail tutorial views.
        typealias Step = TutorialScene.Step

        /// One fake attendee row used in room tutorial scenes.
        struct FakeAttendee {
            /// Stable attendee identifier.
            let id: String
            /// Whether this attendee should map to current signed-in uid.
            let isCurrentUser: Bool
            /// Bilingual attendee display name.
            let name: BilingualText
            /// Friend code shown in attendee row.
            let friendCode: String
            /// Star count shown in attendee row.
            let stars: Int
            /// Deposit honey shown in attendee row.
            let depositHoney: Honey
            /// Greeting message shown for join-request rows.
            let joinGreetingMessage: BilingualText
            /// Attendee state shown by status chip.
            let status: AttendeeStatus
            /// Whether host rating action should be visible.
            let isHostRatingRequired: Bool
            /// Pending confirmation request offsets in seconds before now.
            let pendingConfirmationRequestOffsets: [TimeInterval]
            /// Joined-at offset in seconds before now.
            let joinedAtOffsetSeconds: TimeInterval
        }

        /// Fake room payload used by one room tutorial scene.
        struct FakeRoom {
            /// Stable room identifier.
            let id: String
            /// Bilingual room title.
            let title: BilingualText
            /// Bilingual location.
            let location: BilingualText
            /// Bilingual description.
            let description: BilingualText
            /// Fixed raid cost shown by room actions.
            let fixedRaidCost: Int
            /// Room max player cap.
            let maxPlayers: Int
            /// Last successful raid offset in seconds before now.
            let lastSuccessfulRaidAtOffsetSeconds: TimeInterval
            /// Fake attendees shown in room list.
            let attendees: [FakeAttendee]
        }

        /// Resolved room tutorial scene for the selected language.
        struct Scenario {
            /// Tutorial steps shown in order.
            let steps: [Step]
            /// Fake room payload used while tutorial is active.
            let fakeRoom: FakeRoom
        }

        /// Shared empty greeting text reused by attendee rows without join-request messages.
        static let emptyGreetingText = BilingualText(en: "", cn: "")
        /// Shared host attendee id reused across room-detail tutorial scenes.
        static let sharedHostAttendeeId: String = "tutorial-shared-host"
        /// Shared ready attendee id reused across room-detail tutorial scenes.
        static let sharedReadyAttendeeId: String = "tutorial-shared-ready"
        /// Shared join-request attendee id reused across room-detail tutorial scenes.
        static let sharedJoinRequestAttendeeId: String = "tutorial-shared-join-request"

        /// Builds one resolved room-detail tutorial scenario.
        /// - Parameters:
        ///   - steps: Ordered tutorial steps for this scenario.
        ///   - fakeRoom: Fake room payload rendered while tutorial is active.
        /// - Returns: Scenario payload consumed by room tutorial overlays.
        static func makeScenario(
            steps: [Step],
            fakeRoom: FakeRoom
        ) -> Scenario {
            Scenario(steps: steps, fakeRoom: fakeRoom)
        }

        /// Builds one fake room payload for room-detail tutorials.
        /// - Parameters:
        ///   - id: Stable room id.
        ///   - title: Bilingual room title.
        ///   - location: Bilingual location text.
        ///   - description: Bilingual room description.
        ///   - fixedRaidCost: Honey cost per raid.
        ///   - maxPlayers: Room capacity.
        ///   - lastSuccessfulRaidAtOffsetSeconds: Last successful raid offset from now.
        ///   - attendees: Ordered fake attendee rows.
        /// - Returns: Fake room used by tutorial scenes.
        static func makeFakeRoom(
            id: String,
            title: BilingualText,
            location: BilingualText,
            description: BilingualText,
            fixedRaidCost: Int,
            maxPlayers: Int,
            lastSuccessfulRaidAtOffsetSeconds: TimeInterval,
            attendees: [FakeAttendee]
        ) -> FakeRoom {
            FakeRoom(
                id: id,
                title: title,
                location: location,
                description: description,
                fixedRaidCost: fixedRaidCost,
                maxPlayers: maxPlayers,
                lastSuccessfulRaidAtOffsetSeconds: lastSuccessfulRaidAtOffsetSeconds,
                attendees: attendees
            )
        }

        /// Builds one fake attendee row for room-detail tutorials.
        /// - Parameters:
        ///   - id: Stable attendee id.
        ///   - isCurrentUser: Whether attendee maps to current signed-in user.
        ///   - name: Bilingual attendee display name.
        ///   - friendCode: Friend code shown in row.
        ///   - stars: Star count.
        ///   - depositHoney: Deposited honey amount.
        ///   - status: Attendee status chip value.
        ///   - joinedAtOffsetSeconds: Joined-at offset from now.
        ///   - joinGreetingMessage: Optional greeting message for join-request rows.
        ///   - isHostRatingRequired: Whether host rating action should appear.
        ///   - pendingConfirmationRequestOffsets: Optional confirmation request offsets.
        /// - Returns: Fake attendee row used in tutorial room scenes.
        static func makeFakeAttendee(
            id: String,
            isCurrentUser: Bool,
            name: BilingualText,
            friendCode: String,
            stars: Int,
            depositHoney: Honey,
            status: AttendeeStatus,
            joinedAtOffsetSeconds: TimeInterval,
            joinGreetingMessage: BilingualText = RoomDetailTutorial.emptyGreetingText,
            isHostRatingRequired: Bool = false,
            pendingConfirmationRequestOffsets: [TimeInterval] = []
        ) -> FakeAttendee {
            FakeAttendee(
                id: id,
                isCurrentUser: isCurrentUser,
                name: name,
                friendCode: friendCode,
                stars: stars,
                depositHoney: depositHoney,
                joinGreetingMessage: joinGreetingMessage,
                status: status,
                isHostRatingRequired: isHostRatingRequired,
                pendingConfirmationRequestOffsets: pendingConfirmationRequestOffsets,
                joinedAtOffsetSeconds: joinedAtOffsetSeconds
            )
        }

        /// Builds one shared attendee list reused by both personal and host room-detail tutorials.
        /// - Parameter currentUserAttendeeId: Attendee id that should map to current signed-in uid.
        /// - Returns: Ordered attendee rows for tutorial room scenes.
        static func makeSharedAttendees(currentUserAttendeeId: String) -> [FakeAttendee] {
            [
                makeFakeAttendee(
                    id: sharedHostAttendeeId,
                    isCurrentUser: currentUserAttendeeId == sharedHostAttendeeId,
                    name: BilingualText(en: "John", cn: "桃園彭于晏"),
                    friendCode: "123456789012",
                    stars: 3,
                    depositHoney: 0,
                    status: .host,
                    joinedAtOffsetSeconds: -7200
                ),
                makeFakeAttendee(
                    id: sharedJoinRequestAttendeeId,
                    isCurrentUser: currentUserAttendeeId == sharedJoinRequestAttendeeId,
                    name: BilingualText(en: "Eric", cn: "小宣"),
                    friendCode: "555566667777",
                    stars: 1,
                    depositHoney: 90,
                    status: .askingToJoin,
                    joinedAtOffsetSeconds: -2600,
                    joinGreetingMessage: BilingualText(
                        en: "Hi host, I cannot find mushrooms. Please invite me.",
                        cn: "嗨主持人，我都找不到蘑菇QQ，求邀。"
                    )
                ),
                makeFakeAttendee(
                    id: sharedReadyAttendeeId,
                    isCurrentUser: currentUserAttendeeId == sharedReadyAttendeeId,
                    name: BilingualText(en: "Mei", cn: "小美"),
                    friendCode: "222233334444",
                    stars: 2,
                    depositHoney: 130,
                    status: .ready,
                    joinedAtOffsetSeconds: -3500,
                    pendingConfirmationRequestOffsets: [-1200]
                )
            ]
        }

    }

    /// Shared postcard-detail tutorial configuration primitives.
    enum PostcardDetailTutorial {
        /// Shared step shape alias used by postcard-detail tutorial views.
        typealias Step = TutorialScene.Step

        /// Resolved postcard detail tutorial scene.
        struct Scenario {
            /// Tutorial steps shown in order.
            let steps: [Step]
            /// Fake listing shown while tutorial is active.
            let fakeListing: PostcardListing
            /// Fake buyer order status shown for buyer view when needed.
            let fakeBuyerOrderStatus: PostcardOrderStatus?
            /// Fake pending shipping badge count for seller toolbar indicator.
            let fakePendingShippingCount: Int
        }

    }
}
