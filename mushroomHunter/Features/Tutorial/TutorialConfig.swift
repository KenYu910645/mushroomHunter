//
//  TutorialConfig.swift
//  mushroomHunter
//
//  Purpose:
//  - Centralizes interactive tutorial tuning parameters in one file.
//
//  Defined in this file:
//  - TutorialConfig and Mushroom browse tutorial parameter models.
//
import Foundation
import CoreGraphics

/// Centralized tutorial configuration entry point used by interactive tutorials.
enum TutorialConfig {
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
            titleText.value(for: TutorialConfig.currentLanguage)
        }

        /// Step card description text localized for current language.
        var message: String {
            messageText.value(for: TutorialConfig.currentLanguage)
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
    private static func makeTutorialPostcardDetailListing(
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
            titleText.value(for: TutorialConfig.currentLanguage)
        }

        /// Fake mushroom type localized for current language.
        var mushroomType: String {
            mushroomTypeText.value(for: TutorialConfig.currentLanguage)
        }

        /// Fake location localized for current language.
        var location: String {
            locationText.value(for: TutorialConfig.currentLanguage)
        }
    }

    /// Mushroom browse tutorial configuration.
    enum MushroomBrowse {
        /// Shared step shape alias used by Mushroom browse tutorial views.
        typealias Step = TutorialConfig.Step
        /// Shared fake-room shape alias used by Mushroom browse tutorial scenes.
        typealias FakeRoom = TutorialConfig.BrowseFakeRoom

        /// Full scenario payload resolved for current language.
        struct Scenario {
            /// Tutorial steps shown in order.
            let steps: [Step]
            /// Fake room rows shown in browse list.
            let fakeRooms: [FakeRoom]
            /// Hosted room ids used for ownership badges.
            let hostRoomIds: Set<String>
            /// Joined room ids used for ownership badges.
            let joinedRoomIds: Set<String>
        }

        /// Active scenario selected for current language.
        static var scenario: Scenario {
            return Scenario(
                steps: stepTemplates,
                fakeRooms: fakeRoomTemplates,
                hostRoomIds: hostRoomIds,
                joinedRoomIds: joinedRoomIds
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [Step] = [
            Step(
                highlightTarget: nil,
                title: BilingualText(
                    en: "Mushroom List Tutorial",
                    cn: "組團打蘑菇教學"
                ),
                message: BilingualText(
                    en: "You can search and join mushroom rooms from this list to hunt mushrooms with other players.",
                    cn: "* 玩家可以在列表中搜尋蘑菇房\n* 加入蘑菇房後可以與其他玩家狩獵蘑菇。"
                )
            ),
            Step(
                highlightTarget: .mushroomBrowseHoneyTag,
                title: BilingualText(
                    en: "Honey",
                    cn: "蜂蜜"
                ),
                message: BilingualText(
                    en: "* You need to pay honey to join a room and join mushroom battles.\n* Hosting a room and inviting other players can earn honey.",
                    cn: "* HoneyHub的貨幣\n* 接受蘑菇邀請後需要支付蜂蜜\n* 主持房間並邀請其他玩家可以獲得蜂蜜"
                )
            ),
            Step(
                highlightTarget: .mushroomBrowseSearchButton,
                title: BilingualText(
                    en: "Search",
                    cn: "搜尋功能"
                ),
                message: BilingualText(
                    en: "You can search by room title.",
                    cn: "在列表中搜尋房間標題。"
                )
            ),
            Step(
                highlightTarget: .mushroomBrowseCreateButton,
                title: BilingualText(
                    en: "Tap + to create your host room",
                    cn: "主持房間"
                ),
                message: BilingualText(
                    en: "* After creating a room, you can invite other players.\n* You need Pikmin megaphones to invite room members to help fight mushrooms.",
                    cn: "* 創造房間後可以邀請其他玩家打蘑菇\n* 需消耗Pikmin大聲公來邀請\n* 完成蘑菇邀請後會獲得蜂蜜"
                )
            ),
            Step(
                highlightTarget: .mushroomBrowsePinnedRoomsArea,
                title: BilingualText(
                    en: "Pinned rooms",
                    cn: "置頂功能"
                ),
                message: BilingualText(
                    en: "Rooms you host and rooms you have joined will be pinned to the top.",
                    cn: "已加入或主持的房間會於列表上置頂以方便查看。"
                )
            ),
            Step(
                highlightTarget: .mushroomBrowseJoinableRoomsArea,
                title: BilingualText(
                    en: "Joinable rooms",
                    cn: "房間資訊"
                ),
                message: BilingualText(
                    en: "Tap a room to view detailed room information.",
                    cn: "* 房間標題\n* 主持人所在區域\n* 當前參加人數\n"
                )
            )
        ]

        /// Shared fake room definitions with line-by-line bilingual text.
        private static let fakeRoomTemplates: [FakeRoom] = [
            FakeRoom(
                id: "tutorial-host",
                title: BilingualText(en: "Taipei 101 Mushrooms", cn: "台北101蘑菇"),
                mushroomType: BilingualText(en: "Fire", cn: "火"),
                joinedPlayers: 1,
                maxPlayers: 10,
                hostUid: "tutorial-host-uid",
                hostStars: 3,
                location: BilingualText(en: "Taiwan, Taipei", cn: "台灣, 台北"),
                createdAtOffsetSeconds: -1800,
                lastSuccessfulRaidAtOffsetSeconds: -3600
            ),
            FakeRoom(
                id: "tutorial-joined",
                title: BilingualText(en: "Water mushroom only", cn: "想打水蘑菇的請進"),
                mushroomType: BilingualText(en: "Water", cn: "水"),
                joinedPlayers: 4,
                maxPlayers: 10,
                hostUid: "tutorial-joined-host-uid",
                hostStars: 2,
                location: BilingualText(en: "Japan, Tokyo", cn: "日本, 東京"),
                createdAtOffsetSeconds: -5400,
                lastSuccessfulRaidAtOffsetSeconds: -7200
            ),
            FakeRoom(
                id: "tutorial-general-1",
                title: BilingualText(en: "Invite daily with random mushroom", cn: "每日必邀但隨機蘑菇"),
                mushroomType: BilingualText(en: "Normal", cn: "普通"),
                joinedPlayers: 6,
                maxPlayers: 10,
                hostUid: "tutorial-general-host-1",
                hostStars: 1,
                location: BilingualText(en: "US, Boston", cn: "美國, 波士頓"),
                createdAtOffsetSeconds: -10800,
                lastSuccessfulRaidAtOffsetSeconds: -10800
            ),
            FakeRoom(
                id: "tutorial-general-2",
                title: BilingualText(en: "Mushroom?! whatever...", cn: "佛系打菇"),
                mushroomType: BilingualText(en: "Electric", cn: "電"),
                joinedPlayers: 2,
                maxPlayers: 10,
                hostUid: "tutorial-general-host-2",
                hostStars: 1,
                location: BilingualText(en: "Australia, Sydney", cn: "澳洲, 雪梨"),
                createdAtOffsetSeconds: -14400,
                lastSuccessfulRaidAtOffsetSeconds: -16000
            )
        ]

        /// Hosted room ids used for ownership badges.
        private static let hostRoomIds: Set<String> = ["tutorial-host"]
        /// Joined room ids used for ownership badges.
        private static let joinedRoomIds: Set<String> = ["tutorial-joined"]
    }

    /// Shared room-detail tutorial configuration primitives.
    enum RoomDetailTutorial {
        /// Shared step shape alias used by room-detail tutorial views.
        typealias Step = TutorialConfig.Step

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

    /// Room detail tutorial in personal (non-host) view.
    enum RoomPersonal {
        /// Replay room id used by tutorial catalog destination.
        static let replayRoomId: String = "tutorial-room-personal"

        /// Active scenario selected for current language.
        static var scenario: RoomDetailTutorial.Scenario {
            return RoomDetailTutorial.makeScenario(
                steps: stepTemplates,
                fakeRoom: fakeRoom
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [RoomDetailTutorial.Step] = [
            RoomDetailTutorial.Step(
                highlightTarget: nil,
                title: BilingualText(
                    en: "Mushroom Room Tutorial",
                    cn: "房間頁面教學"
                ),
                message: BilingualText(
                    en: "This page shows room information and attendee status.",
                    cn: "* 加入房間後，主持人如找到空閒蘑菇的話會發出大聲公邀請。"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHeaderSection,
                title: BilingualText(
                    en: "Room header shows key info",
                    cn: "房間資訊"
                ),
                message: BilingualText(
                    en: "Room title, current attendee count, host location, and room description.",
                    cn: "* 房間標題\n* 目前參加人數\n* 主持人所在地點\n* 房間描述"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomAttendeeTopThreeArea,
                title: BilingualText(
                    en: "Attendee list",
                    cn: "成員列表"
                ),
                message: BilingualText(
                    en: "The attendee list below shows all player statuses and each attendee's deposited honey.",
                    cn: "* 所有房間內成員的資訊會列在下方"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHostInfoFriendCodeArea,
                title: BilingualText(
                    en: "Host information",
                    cn: "主持人資訊"
                ),
                message: BilingualText(
                    en: "Check the host's Pikmin ID and friend code. Watch for invites from the host in Pikmin.",
                    cn: "* 主持人的Pikmin ID及Pikmin好友碼\n* 成員需留意來自主持人的蘑菇邀請"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomFirstNonHostStatusStrip,
                title: BilingualText(
                    en: "Other attendee information",
                    cn: "其他成員資訊"
                ),
                message: BilingualText(
                    en: "Shows each attendee's status, deposited honey, and earned stars.",
                    cn: "* 成員ID及好友碼\n* 當前狀態\n* 儲值在房間的蜂蜜\n* 玩家獲得的評價星星"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomAttendeeConfirmationButton,
                title: BilingualText(
                    en: "Invite confirmation queue",
                    cn: "邀請確認管理清單"
                ),
                message: BilingualText(
                    en: "Tap here to open the mushroom invite confirmation list and respond to host invites.",
                    cn: "* 主持人的蘑菇邀請確認會記錄在這\n* 收到蘑菇邀請後請在此處儘速回覆主持人的邀請確認"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomAttendeeEditDepositButton,
                title: BilingualText(
                    en: "Change settings",
                    cn: "變更設定"
                ),
                message: BilingualText(
                    en: "You can update your deposited honey amount or leave the room.",
                    cn: "* 更改儲值的蜂蜜數量\n* 離開房間並返還所有未使用的蜂蜜"
                )
            )
        ]

        /// Fake room reused by personal room-detail tutorial.
        private static let fakeRoom = RoomDetailTutorial.makeFakeRoom(
            id: replayRoomId,
            title: BilingualText(en: "Taipei 101 Mushroom", cn: "台北101蘑菇"),
            location: BilingualText(en: "Taiwan, Taipei", cn: "台灣, 台北"),
            description: BilingualText(
                en: "Host opens raids twice every day. Please keep notifications on.",
                cn: "每天固定下午三點邀請蘑菇，蘑菇顏色大小隨機，請保持通知開啟。"
            ),
            fixedRaidCost: 80,
            maxPlayers: 10,
            lastSuccessfulRaidAtOffsetSeconds: -3600,
            attendees: RoomDetailTutorial.makeSharedAttendees(
                currentUserAttendeeId: RoomDetailTutorial.sharedReadyAttendeeId
            )
        )
    }

    /// Room detail tutorial in host view.
    enum RoomHost {
        /// Replay room id used by tutorial catalog destination.
        static let replayRoomId: String = "tutorial-room-host"

        /// Active scenario selected for current language.
        static var scenario: RoomDetailTutorial.Scenario {
            return RoomDetailTutorial.makeScenario(
                steps: stepTemplates,
                fakeRoom: fakeRoom
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [RoomDetailTutorial.Step] = [
            RoomDetailTutorial.Step(
                highlightTarget: nil,
                title: BilingualText(
                    en: "Room Management Tutorial",
                    cn: "主持房間教學"
                ),
                message: BilingualText(
                    en: "As a host, you can manage attendees here and request invite confirmations from room members.",
                    cn: "* 身為主持人，您可以批准或拒絕其他玩家進入房間\n* 需要消耗Pikmin大聲公邀請房間內所有玩家打蘑菇\n* 邀請完成後可獲得蜂蜜作為報酬"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHeaderSection,
                title: BilingualText(
                    en: "Room header shows key info",
                    cn: "房間資訊"
                ),
                message: BilingualText(
                    en: "Room title, current attendee count, host location, and room description.",
                    cn: "* 房間標題\n* 目前參加人數\n* 主持人所在地點與房間描述"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomAttendeeTopThreeArea,
                title: BilingualText(
                    en: "Attendee list",
                    cn: "成員列表"
                ),
                message: BilingualText(
                    en: "All attendee information is listed here.",
                    cn: "* 所有房間成員的資訊"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomAttendeeRow(index: 1),
                title: BilingualText(
                    en: "Handle join requests",
                    cn: "批准加入申請"
                ),
                message: BilingualText(
                    en: "Players need host approval before joining. After approving, add them as friends in Pikmin for later invites.",
                    cn: "* 其他玩家加入房間前需要主持人同意\n* 同意過後請在Pikmin中加對方好友\n* 下次打蘑菇時請記得邀請新成員"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHostClaimButton,
                title: BilingualText(
                    en: "Send mushroom invite confirmations",
                    cn: "發送蘑菇邀請確認"
                ),
                message: BilingualText(
                    en: "After inviting players in Pikmin, tap here to send confirmations to room members. You earn honey after they confirm.",
                    cn: "* 在Pikmin用大聲公邀請玩家後，點擊此處發送確認給所有房間內的玩家\n* 玩家確認後，主持人會獲得蜂蜜作為報酬。"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHostShareButton,
                title: BilingualText(
                    en: "Share",
                    cn: "分享房間"
                ),
                message: BilingualText(
                    en: "Share the QR code to invite your friends to join the room.",
                    cn: "分享房間二維碼來邀請你的好友加入房間。"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHostRaidHistoryButton,
                title: BilingualText(
                    en: "Confirmation list",
                    cn: "邀請確認清單"
                ),
                message: BilingualText(
                    en: "View attendee invite-confirmation results here.",
                    cn: "在此查看所有參加者的邀請確認結果。"
                )
            ),
            RoomDetailTutorial.Step(
                highlightTarget: .roomHostEditRoomButton,
                title: BilingualText(
                    en: "Edit room settings",
                    cn: "變更房間設定"
                ),
                message: BilingualText(
                    en: "Update room settings or close the room here.",
                    cn: "在此變更房間設定或關閉房間。"
                )
            )
        ]

        /// Fake room reused by host room-detail tutorial.
        private static let fakeRoom = RoomDetailTutorial.makeFakeRoom(
            id: replayRoomId,
            title: BilingualText(en: "Taipei 101 Mushroom", cn: "台北101蘑菇"),
            location: BilingualText(en: "Taiwan, Taipei", cn: "台灣, 台北"),
            description: BilingualText(
                en: "Daily room at 3 PM. Mushroom color and size are random. Please keep notifications enabled.",
                cn: "每天固定下午三點邀請蘑菇，蘑菇顏色大小隨機，請保持通知開啟。"
            ),
            fixedRaidCost: 80,
            maxPlayers: 10,
            lastSuccessfulRaidAtOffsetSeconds: -3600,
            attendees: RoomDetailTutorial.makeSharedAttendees(
                currentUserAttendeeId: RoomDetailTutorial.sharedHostAttendeeId
            )
        )
    }

    /// Shared postcard-browse tutorial configuration primitives.
    enum PostcardBrowse {
        /// Shared step shape alias used by postcard browse tutorial views.
        typealias Step = TutorialConfig.Step

        /// One fake postcard row rendered during tutorial mode.
        struct FakeListing {
            /// Stable listing id used by grid and ownership tagging.
            let id: String
            /// Bilingual listing title.
            let title: BilingualText
            /// Honey price shown in card tag.
            let priceHoney: Int
            /// Bilingual country label.
            let country: BilingualText
            /// Bilingual province/city label.
            let province: BilingualText
            /// Bilingual optional detail label.
            let detail: BilingualText
            /// Fake seller uid.
            let sellerId: String
            /// Bilingual seller display name.
            let sellerName: BilingualText
            /// Fake seller friend code.
            let sellerFriendCode: String
            /// Fake stock count.
            let stock: Int
            /// Relative seconds before now for `createdAt`.
            let createdAtOffsetSeconds: TimeInterval
        }

        /// Full scenario payload resolved for current language.
        struct Scenario {
            /// Tutorial steps shown in order.
            let steps: [Step]
            /// Fake postcard rows shown in browse list.
            let fakeListings: [PostcardListing]
            /// On-shelf listing ids used for ownership tags.
            let onShelfListingIds: Set<String>
            /// Ordered listing ids used for ownership tags.
            let orderedListingIds: Set<String>
        }

        /// Replay postcard id used by tutorial catalog destination.
        static let replayPostcardId: String = "tutorial-postcard-browse-main"

        /// Active scenario selected for current language.
        static var scenario: Scenario {
            let language = TutorialConfig.currentLanguage
            let now = Date()
            return Scenario(
                steps: stepTemplates,
                fakeListings: listingTemplates.map { listing in
                    makeFakePostcardListing(
                        from: listing,
                        language: language,
                        baseDate: now
                    )
                },
                onShelfListingIds: onShelfListingIds,
                orderedListingIds: orderedListingIds
            )
        }

        /// Builds one localized fake postcard listing row for browse tutorial scenes.
        /// - Parameters:
        ///   - listing: Source bilingual listing template.
        ///   - language: Target display language for resolved strings.
        ///   - baseDate: Shared baseline date for deterministic relative timestamps.
        /// - Returns: Localized postcard listing shown in tutorial browse grid.
        private static func makeFakePostcardListing(
            from listing: FakeListing,
            language: Language,
            baseDate: Date
        ) -> PostcardListing {
            PostcardListing(
                id: listing.id,
                sellerId: listing.sellerId,
                title: listing.title.value(for: language),
                priceHoney: listing.priceHoney,
                location: PostcardLocation(
                    country: listing.country.value(for: language),
                    province: listing.province.value(for: language),
                    detail: listing.detail.value(for: language)
                ),
                sellerName: listing.sellerName.value(for: language),
                sellerFriendCode: listing.sellerFriendCode,
                stock: listing.stock,
                imageUrl: nil,
                thumbnailUrl: nil,
                createdAt: baseDate.addingTimeInterval(listing.createdAtOffsetSeconds)
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [Step] = [
            Step(
                highlightTarget: nil,
                title: BilingualText(
                    en: "Welcome to Postcard Browse",
                    cn: "明信片買賣說明"
                ),
                message: BilingualText(
                    en: "This page helps you browse listings, check prices, and register your own postcards.",
                    cn: "* 玩家可以在這個頁面用蜂蜜買賣Pikmin 明信片"
                )
            ),
            Step(
                highlightTarget: .postcardBrowseHoneyTag,
                title: BilingualText(
                    en: "Honey",
                    cn: "蜂蜜"
                ),
                message: BilingualText(
                    en: "* You need to pay honey to join a room and join mushroom battles.\n* Hosting a room and inviting other players can earn honey.",
                    cn: "* 購買明信片需要支付蜂蜜\n* 販賣明信片可以獲得蜂蜜"
                )
            ),
            Step(
                highlightTarget: .postcardBrowseSearchButton,
                title: BilingualText(
                    en: "Search",
                    cn: "搜尋功能"
                ),
                message: BilingualText(
                    en: "You can search by room title.",
                    cn: "在列表中搜尋明信片標題。"
                )
            ),
            Step(
                highlightTarget: .postcardBrowseCreateButton,
                title: BilingualText(
                    en: "Tap + to create your host room",
                    cn: "上架明信片"
                ),
                message: BilingualText(
                    en: "* After creating a room, you can invite other players.\n* You need Pikmin megaphones to invite room members to help fight mushrooms.",
                    cn: "* 上傳明信片預覽圖片\n* 加買家好友之後即可送出明信片。"
                )
            ),
            Step(
                highlightTarget: .postcardBrowsePinnedOwnershipArea,
                title: BilingualText(
                    en: "Pinned ownership cards",
                    cn: "明信片資訊"
                ),
                message: BilingualText(
                    en: "On-shelf and Ordered cards are pinned first so you can track your own trading state.",
                    cn: "販賣價格(蜂蜜)與明信片地點。"
                )
            ),
            Step(
                highlightTarget: .postcardBrowsePinnedOwnershipArea,
                title: BilingualText(
                    en: "Pinned ownership cards",
                    cn: "置頂明信片"
                ),
                message: BilingualText(
                    en: "On-shelf and Ordered cards are pinned first so you can track your own trading state.",
                    cn: "已上架與已下單的明信片會在瀏覽列表上置頂，方便查看。"
                )
            )
        ]

        /// Shared fake listing definitions with line-by-line bilingual text.
        private static let listingTemplates: [FakeListing] = [
            FakeListing(
                id: replayPostcardId,
                title: BilingualText(en: "Central Park Pikmin Card", cn: "中央公園皮克敏卡"),
                priceHoney: 60,
                country: BilingualText(en: "US", cn: "US"),
                province: BilingualText(en: "New York", cn: "紐約"),
                detail: BilingualText(en: "Near lake area", cn: "湖邊附近"),
                sellerId: "tutorial-postcard-self-seller",
                sellerName: BilingualText(en: "You", cn: "你"),
                sellerFriendCode: "222233334444",
                stock: 2,
                createdAtOffsetSeconds: -1200
            ),
            FakeListing(
                id: "tutorial-postcard-ordered",
                title: BilingualText(en: "Downtown Night Event Card", cn: "市中心夜間活動卡"),
                priceHoney: 80,
                country: BilingualText(en: "US", cn: "US"),
                province: BilingualText(en: "Seattle", cn: "西雅圖"),
                detail: BilingualText(en: "Space Needle", cn: "太空針塔"),
                sellerId: "tutorial-postcard-seller-2",
                sellerName: BilingualText(en: "Nina", cn: "Nina"),
                sellerFriendCode: "111122223333",
                stock: 1,
                createdAtOffsetSeconds: -2800
            ),
            FakeListing(
                id: "tutorial-postcard-general-1",
                title: BilingualText(en: "Harbor Sunrise Card", cn: "港口日出卡"),
                priceHoney: 50,
                country: BilingualText(en: "US", cn: "US"),
                province: BilingualText(en: "Boston", cn: "波士頓"),
                detail: BilingualText(en: "", cn: ""),
                sellerId: "tutorial-postcard-seller-3",
                sellerName: BilingualText(en: "Ming", cn: "小明"),
                sellerFriendCode: "555566667777",
                stock: 3,
                createdAtOffsetSeconds: -4800
            ),
            FakeListing(
                id: "tutorial-postcard-general-2",
                title: BilingualText(en: "Rainy Day Station Card", cn: "雨天車站卡"),
                priceHoney: 70,
                country: BilingualText(en: "US", cn: "US"),
                province: BilingualText(en: "Chicago", cn: "芝加哥"),
                detail: BilingualText(en: "", cn: ""),
                sellerId: "tutorial-postcard-seller-4",
                sellerName: BilingualText(en: "Alex", cn: "Alex"),
                sellerFriendCode: "888899990000",
                stock: 1,
                createdAtOffsetSeconds: -7200
            )
        ]

        /// On-shelf listing ids used for ownership tags.
        private static let onShelfListingIds: Set<String> = [replayPostcardId]
        /// Ordered listing ids used for ownership tags.
        private static let orderedListingIds: Set<String> = ["tutorial-postcard-ordered"]
    }

    /// Shared postcard-detail tutorial configuration primitives.
    enum PostcardDetailTutorial {
        /// Shared step shape alias used by postcard-detail tutorial views.
        typealias Step = TutorialConfig.Step

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

    /// Postcard detail tutorial in buyer view.
    enum PostcardBuyer {
        /// Replay postcard id used by tutorial catalog destination.
        static let replayPostcardId: String = "tutorial-postcard-buyer"

        /// Active scenario selected for current language.
        static var scenario: PostcardDetailTutorial.Scenario {
            return PostcardDetailTutorial.Scenario(
                steps: stepTemplates,
                fakeListing: TutorialConfig.makeTutorialPostcardDetailListing(
                    id: replayPostcardId,
                    sellerId: "tutorial-postcard-buyer-seller",
                    title: listingTitle,
                    priceHoney: 75,
                    country: listingCountry,
                    province: listingProvince,
                    detail: listingDetail,
                    sellerName: listingSellerName,
                    sellerFriendCode: "123456789012",
                    stock: 2,
                    createdAtOffsetSeconds: -1500
                ),
                fakeBuyerOrderStatus: nil,
                fakePendingShippingCount: 0
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [PostcardDetailTutorial.Step] = [
            PostcardDetailTutorial.Step(
                highlightTarget: nil,
                title: BilingualText(
                    en: "Welcome to Postcard Detail",
                    cn: "明信片購買教學"
                ),
                message: BilingualText(
                    en: "This page shows postcard details and buyer actions for placing or confirming an order.",
                    cn: "* 用蜂蜜向其他玩家購買明信片\n* 在Pikmin中加好友後賣家即可寄送明信片"
                )
            ),
            PostcardDetailTutorial.Step(
                highlightTarget: .postcardDetailInfoSection, //// TODO: the target needs to be the postcard snapshot
                title: BilingualText(
                    en: "Check title, price, and seller info",
                    cn: "先查看卡片名稱、價格與賣家資訊"
                ),
                message: BilingualText(
                    en: "Confirm postcard info and friend code before placing your order.",
                    cn: "下單前先確認卡片資訊與好友碼。"
                )
            ),
            PostcardDetailTutorial.Step(
                highlightTarget: .postcardDetailInfoSection,
                title: BilingualText(
                    en: "Check title, price, and seller info",
                    cn: "先查看卡片名稱、價格與賣家資訊"
                ),
                message: BilingualText(
                    en: "Confirm postcard info and friend code before placing your order.",
                    cn: "下單前先確認卡片資訊與好友碼。"
                )
            ),
            PostcardDetailTutorial.Step(
                highlightTarget: .postcardBuyerBuyButton,
                title: BilingualText(
                    en: "Buy action starts order flow",
                    cn: "點擊購買可開始下單流程"
                ),
                message: BilingualText(
                    en: "Use this button to place an order. Shipping and receive status will update here later.",
                    cn: "點此可送出訂單，後續寄送與收件狀態也會在此更新。"
                )
            )
        ]

        /// Buyer tutorial fake listing title.
        private static let listingTitle = BilingualText(en: "Riverside Lantern Card", cn: "養鴨人家")
        /// Buyer tutorial fake listing country.
        private static let listingCountry = BilingualText(en: "Taiwan", cn: "台灣")
        /// Buyer tutorial fake listing province.
        private static let listingProvince = BilingualText(en: "Taoyuan", cn: "桃園")
        /// Buyer tutorial fake listing detail.
        private static let listingDetail = BilingualText(en: "Come and buy it!", cn: "大家快來買！")
        /// Buyer tutorial fake seller name.
        private static let listingSellerName = BilingualText(en: "Lily", cn: "小明")
    }

    /// Postcard detail tutorial in seller view.
    enum PostcardSeller {
        /// Replay postcard id used by tutorial catalog destination.
        static let replayPostcardId: String = "tutorial-postcard-seller"

        /// Active scenario selected for current language.
        static var scenario: PostcardDetailTutorial.Scenario {
            return PostcardDetailTutorial.Scenario(
                steps: stepTemplates,
                fakeListing: TutorialConfig.makeTutorialPostcardDetailListing(
                    id: replayPostcardId,
                    sellerId: "tutorial-postcard-seller-self",
                    title: listingTitle,
                    priceHoney: 90,
                    country: listingCountry,
                    province: listingProvince,
                    detail: listingDetail,
                    sellerName: listingSellerName,
                    sellerFriendCode: "222233334444",
                    stock: 3,
                    createdAtOffsetSeconds: -1800
                ),
                fakeBuyerOrderStatus: nil,
                fakePendingShippingCount: 2
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [PostcardDetailTutorial.Step] = [
            PostcardDetailTutorial.Step(
                highlightTarget: nil,
                title: BilingualText(
                    en: "Welcome to Seller Postcard View",
                    cn: "歡迎來到賣家明信片頁"
                ),
                message: BilingualText(
                    en: "As a seller, you can manage shipping, share invite links, and edit listing info here.",
                    cn: "身為賣家，您可在此管理出貨、分享邀請連結並編輯卡片資訊。"
                )
            ),
            PostcardDetailTutorial.Step(
                highlightTarget: .postcardSellerShippingButton,
                title: BilingualText(
                    en: "Seller toolbar actions",
                    cn: "賣家工具列功能"
                ),
                message: BilingualText(
                    en: "Share invite, open shipping queue, and edit listing from top-right actions.",
                    cn: "可從右上角快速分享邀請、查看出貨佇列與編輯卡片。"
                )
            ),
            PostcardDetailTutorial.Step(
                highlightTarget: .postcardDetailInfoSection,
                title: BilingualText(
                    en: "Keep listing info accurate",
                    cn: "維持卡片資訊正確"
                ),
                message: BilingualText(
                    en: "Buyers rely on title, location, and stock shown in this section.",
                    cn: "買家會依據這裡的名稱、地點與庫存資訊決定是否下單。"
                )
            )
        ]

        /// Seller tutorial fake listing title.
        private static let listingTitle = BilingualText(en: "City Hall Event Card", cn: "市政廳活動卡")
        /// Seller tutorial fake listing country.
        private static let listingCountry = BilingualText(en: "US", cn: "US")
        /// Seller tutorial fake listing province.
        private static let listingProvince = BilingualText(en: "Los Angeles", cn: "洛杉磯")
        /// Seller tutorial fake listing detail.
        private static let listingDetail = BilingualText(en: "Downtown Plaza", cn: "市中心廣場")
        /// Seller tutorial fake seller name.
        private static let listingSellerName = BilingualText(en: "You", cn: "你")
    }
}
