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
        /// English tutorial copy and fake scene content.
        case en
        /// Traditional Chinese tutorial copy and fake scene content.
        case cn
    }

    /// One line-by-line bilingual text entry.
    struct BilingualText {
        /// English copy.
        let en: String
        /// Traditional Chinese copy.
        let cn: String

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

    /// Returns tutorial language based on current preferred system language.
    static var currentLanguage: Language {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        let isTraditionalChinese = preferredLanguage.contains("zh-hant")
            || preferredLanguage.contains("zh-tw")
            || preferredLanguage.contains("zh-hk")
        return isTraditionalChinese ? .cn : .en
    }

    /// Mushroom browse tutorial configuration.
    enum MushroomBrowse {
        /// One message-card + highlight step in the tutorial flow.
        struct Step {
            /// Optional live highlight target resolved from anchored UI elements.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional fallback rectangle in normalized screen coordinates when live anchor is unavailable.
            let normalizedRect: CGRect?
            /// Message card vertical position in normalized screen coordinates.
            let messageBoxNormalizedY: CGFloat
            /// Step card title text.
            let title: String
            /// Step card description text.
            let message: String
        }

        /// One fake room row rendered during tutorial mode.
        struct FakeRoom {
            /// Stable room id used by list and ownership tagging.
            let id: String
            /// Fake room title.
            let title: String
            /// Fake mushroom type text.
            let mushroomType: String
            /// Fake joined attendee count.
            let joinedPlayers: Int
            /// Fake room attendee cap.
            let maxPlayers: Int
            /// Fake host uid for room model shape.
            let hostUid: String
            /// Fake host stars used by sorting.
            let hostStars: Int
            /// Fake location text rendered in browse row.
            let location: String
            /// Relative seconds before now for `createdAt`.
            let createdAtOffsetSeconds: TimeInterval
            /// Relative seconds before now for `lastSuccessfulRaidAt`.
            let lastSuccessfulRaidAtOffsetSeconds: TimeInterval
        }

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

        /// Internal step template that keeps EN/zh-Hant text on the same line block.
        private struct StepTemplate {
            /// Optional shared live highlight target for all languages.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional shared fallback rectangle for all languages. Nil means full-screen highlight.
            let normalizedRect: CGRect?
            /// Shared message card vertical position for all languages.
            let messageBoxNormalizedY: CGFloat
            /// Bilingual title text.
            let title: BilingualText
            /// Bilingual message text.
            let message: BilingualText
        }

        /// Internal fake-room template that keeps EN/zh-Hant text on the same line block.
        private struct FakeRoomTemplate {
            /// Stable room id used by list and ownership tagging.
            let id: String
            /// Bilingual room title.
            let title: BilingualText
            /// Bilingual mushroom type text.
            let mushroomType: BilingualText
            /// Fake joined attendee count.
            let joinedPlayers: Int
            /// Fake room attendee cap.
            let maxPlayers: Int
            /// Fake host uid for room model shape.
            let hostUid: String
            /// Fake host stars used by sorting.
            let hostStars: Int
            /// Bilingual location text rendered in browse row.
            let location: BilingualText
            /// Relative seconds before now for `createdAt`.
            let createdAtOffsetSeconds: TimeInterval
            /// Relative seconds before now for `lastSuccessfulRaidAt`.
            let lastSuccessfulRaidAtOffsetSeconds: TimeInterval
        }

        /// Active scenario selected for current language.
        static var scenario: Scenario {
            let language = TutorialConfig.currentLanguage
            return Scenario(
                steps: stepTemplates.map { step in
                    Step(
                        highlightTarget: step.highlightTarget,
                        normalizedRect: step.normalizedRect,
                        messageBoxNormalizedY: step.messageBoxNormalizedY,
                        title: step.title.value(for: language),
                        message: step.message.value(for: language)
                    )
                },
                fakeRooms: fakeRoomTemplates.map { room in
                    FakeRoom(
                        id: room.id,
                        title: room.title.value(for: language),
                        mushroomType: room.mushroomType.value(for: language),
                        joinedPlayers: room.joinedPlayers,
                        maxPlayers: room.maxPlayers,
                        hostUid: room.hostUid,
                        hostStars: room.hostStars,
                        location: room.location.value(for: language),
                        createdAtOffsetSeconds: room.createdAtOffsetSeconds,
                        lastSuccessfulRaidAtOffsetSeconds: room.lastSuccessfulRaidAtOffsetSeconds
                    )
                },
                hostRoomIds: hostRoomIds,
                joinedRoomIds: joinedRoomIds
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [StepTemplate] = [
            StepTemplate(
                highlightTarget: nil,
                normalizedRect: nil,
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Mushroom List Tutorial",
                    cn: "蘑菇房列表教學"
                ),
                message: BilingualText(
                    en: "1. Mushroom rooms are created by players who have extra mushrooms.\n2. Players who cannot find mushrooms can join a room and wait for the host to invite them with the megaphone.\n3. After receiving an invite, players pay honey to the host; hosting rooms and inviting players can earn honey.",
                    cn: "玩家可以加入蘑菇房與其他玩家一起狩獵蘑菇。"
                )
            ),
            StepTemplate(
                highlightTarget: .mushroomBrowseHoneyTag,
                normalizedRect: CGRect(x: 0.02, y: 0.20, width: 0.1, height: 0.09),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Your honey",
                    cn: "你的蜂蜜"
                ),
                message: BilingualText(
                    en: "You need to pay honey to join a room and join a mushroom battle. Hosting rooms and inviting other players can earn honey.",
                    cn: "加入房間參加蘑菇戰需要支付蜂蜜，而主持房間並邀請其他玩家可以賺取蜂蜜"
                )
            ),
            StepTemplate(
                highlightTarget: .mushroomBrowseSearchButton,
                normalizedRect: CGRect(x: 0.02, y: 0.32, width: 0.96, height: 0.30),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Search",
                    cn: "搜尋功能"
                ),
                message: BilingualText(
                    en: "You can search by room title.",
                    cn: "在這裡可以搜尋房間標題。"
                )
            ),
            StepTemplate(
                highlightTarget: .mushroomBrowseCreateButton,
                normalizedRect: CGRect(x: 0.79, y: 0.20, width: 0.17, height: 0.09),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Tap + to create your host room",
                    cn: "創造你的房間"
                ),
                message: BilingualText(
                    en: "Create room, set location and rules, then invite your Pikmin Bloom friends.",
                    cn: "創造房間後可以邀請其他玩家進入房間，並用Pikmin大聲公邀請房間內的玩家幫忙打蘑菇"
                )
            ),
            StepTemplate(
                highlightTarget: .mushroomBrowsePinnedRoomsArea,
                normalizedRect: CGRect(x: 0.79, y: 0.20, width: 0.17, height: 0.09),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Pinned rooms",
                    cn: "置頂功能"
                ),
                message: BilingualText(
                    en: "Rooms you host and rooms you have joined will be pinned to the top.",
                    cn: "創造的房間跟已加入的房間會於列表上置頂以方便查看"
                )
            ),
            StepTemplate(
                highlightTarget: .mushroomBrowseJoinableRoomsArea,
                normalizedRect: CGRect(x: 0.79, y: 0.20, width: 0.17, height: 0.09),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Joinable rooms",
                    cn: "房間資訊"
                ),
                message: BilingualText(
                    en: "This list shows each mushroom's approximate location and attendee count.",
                    cn: "主持人所在位置跟參加人數"
                )
            )
        ]

        /// Shared fake room definitions with line-by-line bilingual text.
        private static let fakeRoomTemplates: [FakeRoomTemplate] = [
            FakeRoomTemplate(
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
            FakeRoomTemplate(
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
            FakeRoomTemplate(
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
            FakeRoomTemplate(
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
        /// One message-card + highlight step in a room tutorial flow.
        struct Step {
            /// Optional live highlight target resolved from anchored UI elements.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional fallback rectangle in normalized screen coordinates. Nil means no highlight cutout.
            let normalizedRect: CGRect?
            /// Message card vertical position in normalized screen coordinates.
            let messageBoxNormalizedY: CGFloat
            /// Step card title text.
            let title: String
            /// Step card description text.
            let message: String
        }

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
            /// Target mushroom color.
            let targetColor: MushroomColor
            /// Target mushroom attribute.
            let targetAttribute: MushroomAttribute
            /// Target mushroom size.
            let targetSize: MushroomSize
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

        /// Internal step template with side-by-side bilingual text.
        struct StepTemplate {
            /// Optional shared live highlight target for all languages.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional shared fallback rectangle for all languages. Nil means no highlight cutout.
            let normalizedRect: CGRect?
            /// Shared message card vertical position for all languages.
            let messageBoxNormalizedY: CGFloat
            /// Bilingual step title.
            let title: BilingualText
            /// Bilingual step description.
            let message: BilingualText
        }
    }

    /// Room detail tutorial in personal (non-host) view.
    enum RoomPersonal {
        /// Replay room id used by tutorial catalog destination.
        static let replayRoomId: String = "tutorial-room-personal"

        /// Active scenario selected for current language.
        static var scenario: RoomDetailTutorial.Scenario {
            let language = TutorialConfig.currentLanguage
            return RoomDetailTutorial.Scenario(
                steps: stepTemplates.map { step in
                    RoomDetailTutorial.Step(
                        highlightTarget: step.highlightTarget,
                        normalizedRect: step.normalizedRect,
                        messageBoxNormalizedY: step.messageBoxNormalizedY,
                        title: step.title.value(for: language),
                        message: step.message.value(for: language)
                    )
                },
                fakeRoom: fakeRoom
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [RoomDetailTutorial.StepTemplate] = [
            RoomDetailTutorial.StepTemplate(
                highlightTarget: nil,
                normalizedRect: nil,
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Welcome to Room View",
                    cn: "歡迎來到房間頁面"
                ),
                message: BilingualText(
                    en: "This page shows room details, attendee status, and your actions before each raid.",
                    cn: "這個頁面會顯示房間資訊、參加者狀態，以及開戰前可執行的操作。"
                )
            ),
            RoomDetailTutorial.StepTemplate(
                highlightTarget: .roomHeaderSection,
                normalizedRect: CGRect(x: 0.04, y: 0.16, width: 0.92, height: 0.20),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Room header shows key info",
                    cn: "房間標頭會顯示重點資訊"
                ),
                message: BilingualText(
                    en: "You can quickly check title, attendee count, location, and room description here.",
                    cn: "這裡可快速查看房名、人數、地點與房間描述。"
                )
            ),
            RoomDetailTutorial.StepTemplate(
                highlightTarget: .roomAttendeeSection,
                normalizedRect: CGRect(x: 0.04, y: 0.33, width: 0.92, height: 0.46),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Attendee list shows room status",
                    cn: "參加者列表可查看房間狀態"
                ),
                message: BilingualText(
                    en: "Check who is host, who is ready, and each attendee deposit before joining raids.",
                    cn: "可查看誰是主持、誰已準備好，以及每位參加者的儲值蜂蜜。"
                )
            ),
            RoomDetailTutorial.StepTemplate(
                highlightTarget: .roomAttendeeConfirmationButton,
                normalizedRect: CGRect(x: 0.70, y: 0.04, width: 0.26, height: 0.08),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Top-right tools are for attendees",
                    cn: "右上工具是參加者常用功能"
                ),
                message: BilingualText(
                    en: "Use these buttons to open confirmation queue and edit your deposit.",
                    cn: "可在此開啟確認佇列，或編輯您在房間中的儲值。"
                )
            )
        ]

        /// Fake room reused by personal room-detail tutorial.
        private static let fakeRoom = RoomDetailTutorial.FakeRoom(
            id: replayRoomId,
            title: BilingualText(en: "Central Park Afternoon Raid", cn: "中央公園午後團"),
            location: BilingualText(en: "US, New York", cn: "US, 紐約"),
            description: BilingualText(
                en: "Host opens raids twice every day. Please keep notifications on.",
                cn: "主持人每天開兩次蘑菇戰，請保持通知開啟。"
            ),
            targetColor: .Blue,
            targetAttribute: .Water,
            targetSize: .Normal,
            fixedRaidCost: 80,
            maxPlayers: 10,
            lastSuccessfulRaidAtOffsetSeconds: -3600,
            attendees: [
                RoomDetailTutorial.FakeAttendee(
                    id: "tutorial-host-attendee",
                    isCurrentUser: false,
                    name: BilingualText(en: "Host Lily", cn: "主持人 Lily"),
                    friendCode: "123456789012",
                    stars: 3,
                    depositHoney: 0,
                    joinGreetingMessage: BilingualText(en: "", cn: ""),
                    status: .host,
                    isHostRatingRequired: false,
                    pendingConfirmationRequestOffsets: [],
                    joinedAtOffsetSeconds: -7200
                ),
                RoomDetailTutorial.FakeAttendee(
                    id: "tutorial-self-attendee",
                    isCurrentUser: true,
                    name: BilingualText(en: "You", cn: "你"),
                    friendCode: "222233334444",
                    stars: 2,
                    depositHoney: 130,
                    joinGreetingMessage: BilingualText(
                        en: "Hi host, I can join quickly.",
                        cn: "嗨主持人，我可以很快加入。"
                    ),
                    status: .ready,
                    isHostRatingRequired: false,
                    pendingConfirmationRequestOffsets: [-1200],
                    joinedAtOffsetSeconds: -3500
                ),
                RoomDetailTutorial.FakeAttendee(
                    id: "tutorial-other-attendee",
                    isCurrentUser: false,
                    name: BilingualText(en: "Ming", cn: "小明"),
                    friendCode: "555566667777",
                    stars: 1,
                    depositHoney: 90,
                    joinGreetingMessage: BilingualText(en: "", cn: ""),
                    status: .ready,
                    isHostRatingRequired: false,
                    pendingConfirmationRequestOffsets: [],
                    joinedAtOffsetSeconds: -2600
                )
            ]
        )
    }

    /// Room detail tutorial in host view.
    enum RoomHost {
        /// Replay room id used by tutorial catalog destination.
        static let replayRoomId: String = "tutorial-room-host"

        /// Active scenario selected for current language.
        static var scenario: RoomDetailTutorial.Scenario {
            let language = TutorialConfig.currentLanguage
            return RoomDetailTutorial.Scenario(
                steps: stepTemplates.map { step in
                    RoomDetailTutorial.Step(
                        highlightTarget: step.highlightTarget,
                        normalizedRect: step.normalizedRect,
                        messageBoxNormalizedY: step.messageBoxNormalizedY,
                        title: step.title.value(for: language),
                        message: step.message.value(for: language)
                    )
                },
                fakeRoom: fakeRoom
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [RoomDetailTutorial.StepTemplate] = [
            RoomDetailTutorial.StepTemplate(
                highlightTarget: nil,
                normalizedRect: nil,
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Welcome to Host Room View",
                    cn: "歡迎來到主持房間頁面"
                ),
                message: BilingualText(
                    en: "As host, this page helps you manage attendees and complete raid settlement.",
                    cn: "身為主持人，您可在此管理參加者並完成蘑菇戰結算。"
                )
            ),
            RoomDetailTutorial.StepTemplate(
                highlightTarget: .roomHostShareButton,
                normalizedRect: CGRect(x: 0.66, y: 0.04, width: 0.30, height: 0.08),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Host toolbar actions",
                    cn: "主持人工具列功能"
                ),
                message: BilingualText(
                    en: "Share invite, open raid history, and edit room settings from here.",
                    cn: "可從這裡分享邀請、查看歷史紀錄、編輯房間設定。"
                )
            ),
            RoomDetailTutorial.StepTemplate(
                highlightTarget: .roomAttendeeSection,
                normalizedRect: CGRect(x: 0.04, y: 0.33, width: 0.92, height: 0.46),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Review attendees and requests",
                    cn: "檢視參加者與申請狀態"
                ),
                message: BilingualText(
                    en: "Join requests and attendee statuses appear here so hosts can manage the room.",
                    cn: "加入申請與參加者狀態都會顯示在這裡，方便主持人管理。"
                )
            ),
            RoomDetailTutorial.StepTemplate(
                highlightTarget: .roomHostClaimButton,
                normalizedRect: CGRect(x: 0.04, y: 0.86, width: 0.92, height: 0.09),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Finish raid to settle rewards",
                    cn: "完成蘑菇戰後可結算獎勵"
                ),
                message: BilingualText(
                    en: "After inviting attendees, use this button to start confirmation and settlement.",
                    cn: "邀請完成後可用此按鈕發送確認並進行結算。"
                )
            )
        ]

        /// Fake room reused by host room-detail tutorial.
        private static let fakeRoom = RoomDetailTutorial.FakeRoom(
            id: replayRoomId,
            title: BilingualText(en: "Downtown Giant Mushroom", cn: "市中心巨大蘑菇"),
            location: BilingualText(en: "US, New York", cn: "US, 紐約"),
            description: BilingualText(
                en: "Host room for daily giant mushroom runs.",
                cn: "每日巨大蘑菇團主持房。"
            ),
            targetColor: .Red,
            targetAttribute: .Fire,
            targetSize: .Magnificent,
            fixedRaidCost: 100,
            maxPlayers: 10,
            lastSuccessfulRaidAtOffsetSeconds: -5400,
            attendees: [
                RoomDetailTutorial.FakeAttendee(
                    id: "tutorial-self-host",
                    isCurrentUser: true,
                    name: BilingualText(en: "You", cn: "你"),
                    friendCode: "222233334444",
                    stars: 3,
                    depositHoney: 0,
                    joinGreetingMessage: BilingualText(en: "", cn: ""),
                    status: .host,
                    isHostRatingRequired: false,
                    pendingConfirmationRequestOffsets: [],
                    joinedAtOffsetSeconds: -9000
                ),
                RoomDetailTutorial.FakeAttendee(
                    id: "tutorial-ready-attendee",
                    isCurrentUser: false,
                    name: BilingualText(en: "Alex", cn: "Alex"),
                    friendCode: "888899990000",
                    stars: 2,
                    depositHoney: 150,
                    joinGreetingMessage: BilingualText(en: "", cn: ""),
                    status: .ready,
                    isHostRatingRequired: false,
                    pendingConfirmationRequestOffsets: [],
                    joinedAtOffsetSeconds: -4200
                ),
                RoomDetailTutorial.FakeAttendee(
                    id: "tutorial-join-request",
                    isCurrentUser: false,
                    name: BilingualText(en: "Nina", cn: "Nina"),
                    friendCode: "111122223333",
                    stars: 1,
                    depositHoney: 100,
                    joinGreetingMessage: BilingualText(
                        en: "Hi host, please let me join your next run.",
                        cn: "嗨主持人，想加入你下一場蘑菇戰。"
                    ),
                    status: .askingToJoin,
                    isHostRatingRequired: false,
                    pendingConfirmationRequestOffsets: [],
                    joinedAtOffsetSeconds: -1200
                )
            ]
        )
    }

    /// Shared postcard-browse tutorial configuration primitives.
    enum PostcardBrowse {
        /// One message-card + highlight step in postcard browse tutorial flow.
        struct Step {
            /// Optional live highlight target resolved from anchored UI elements.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional fallback rectangle in normalized screen coordinates. Nil means no highlight cutout.
            let normalizedRect: CGRect?
            /// Message card vertical position in normalized screen coordinates.
            let messageBoxNormalizedY: CGFloat
            /// Step card title text.
            let title: String
            /// Step card description text.
            let message: String
        }

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

        /// Internal step template with side-by-side bilingual text.
        private struct StepTemplate {
            /// Optional shared live highlight target for all languages.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional shared fallback rectangle for all languages. Nil means no highlight cutout.
            let normalizedRect: CGRect?
            /// Shared message card vertical position for all languages.
            let messageBoxNormalizedY: CGFloat
            /// Bilingual step title.
            let title: BilingualText
            /// Bilingual step description.
            let message: BilingualText
        }

        /// Replay postcard id used by tutorial catalog destination.
        static let replayPostcardId: String = "tutorial-postcard-browse-main"

        /// Active scenario selected for current language.
        static var scenario: Scenario {
            let language = TutorialConfig.currentLanguage
            let now = Date()
            return Scenario(
                steps: stepTemplates.map { step in
                    Step(
                        highlightTarget: step.highlightTarget,
                        normalizedRect: step.normalizedRect,
                        messageBoxNormalizedY: step.messageBoxNormalizedY,
                        title: step.title.value(for: language),
                        message: step.message.value(for: language)
                    )
                },
                fakeListings: listingTemplates.map { listing in
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
                        createdAt: now.addingTimeInterval(listing.createdAtOffsetSeconds)
                    )
                },
                onShelfListingIds: onShelfListingIds,
                orderedListingIds: orderedListingIds
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [StepTemplate] = [
            StepTemplate(
                highlightTarget: nil,
                normalizedRect: nil,
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Welcome to Postcard Browse",
                    cn: "歡迎來到明信片列表"
                ),
                message: BilingualText(
                    en: "This page helps you browse listings, check prices, and register your own postcards.",
                    cn: "這個頁面可瀏覽明信片、查看價格，並快速上架自己的明信片。"
                )
            ),
            StepTemplate(
                highlightTarget: .postcardBrowseTopActionBar,
                normalizedRect: CGRect(x: 0.02, y: 0.20, width: 0.96, height: 0.09),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Top bar actions",
                    cn: "上方列功能"
                ),
                message: BilingualText(
                    en: "Use search to find postcards and tap + to register a new postcard listing.",
                    cn: "可用搜尋快速找卡片，也可點 + 上架新的明信片。"
                )
            ),
            StepTemplate(
                highlightTarget: .postcardBrowsePinnedOwnershipArea,
                normalizedRect: CGRect(x: 0.02, y: 0.31, width: 0.96, height: 0.56),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Pinned ownership cards",
                    cn: "固定顯示的擁有卡片"
                ),
                message: BilingualText(
                    en: "On-shelf and Ordered cards are pinned first so you can track your own trading state.",
                    cn: "已上架與已下單卡片會固定在前面，方便追蹤自己的交易狀態。"
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
        /// One message-card + highlight step in postcard detail tutorial flow.
        struct Step {
            /// Optional live highlight target resolved from anchored UI elements.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional fallback rectangle in normalized screen coordinates. Nil means no highlight cutout.
            let normalizedRect: CGRect?
            /// Message card vertical position in normalized screen coordinates.
            let messageBoxNormalizedY: CGFloat
            /// Step card title text.
            let title: String
            /// Step card description text.
            let message: String
        }

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

        /// Internal step template with side-by-side bilingual text.
        struct StepTemplate {
            /// Optional shared live highlight target for all languages.
            let highlightTarget: TutorialHighlightTarget?
            /// Optional shared fallback rectangle for all languages.
            let normalizedRect: CGRect?
            /// Shared message card vertical position for all languages.
            let messageBoxNormalizedY: CGFloat
            /// Bilingual step title.
            let title: BilingualText
            /// Bilingual step description.
            let message: BilingualText
        }
    }

    /// Postcard detail tutorial in buyer view.
    enum PostcardBuyer {
        /// Replay postcard id used by tutorial catalog destination.
        static let replayPostcardId: String = "tutorial-postcard-buyer"

        /// Active scenario selected for current language.
        static var scenario: PostcardDetailTutorial.Scenario {
            let language = TutorialConfig.currentLanguage
            return PostcardDetailTutorial.Scenario(
                steps: stepTemplates.map { step in
                    PostcardDetailTutorial.Step(
                        highlightTarget: step.highlightTarget,
                        normalizedRect: step.normalizedRect,
                        messageBoxNormalizedY: step.messageBoxNormalizedY,
                        title: step.title.value(for: language),
                        message: step.message.value(for: language)
                    )
                },
                fakeListing: PostcardListing(
                    id: replayPostcardId,
                    sellerId: "tutorial-postcard-buyer-seller",
                    title: listingTitle.value(for: language),
                    priceHoney: 75,
                    location: PostcardLocation(
                        country: listingCountry.value(for: language),
                        province: listingProvince.value(for: language),
                        detail: listingDetail.value(for: language)
                    ),
                    sellerName: listingSellerName.value(for: language),
                    sellerFriendCode: "123456789012",
                    stock: 2,
                    imageUrl: nil,
                    thumbnailUrl: nil,
                    createdAt: Date().addingTimeInterval(-1500)
                ),
                fakeBuyerOrderStatus: nil,
                fakePendingShippingCount: 0
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [PostcardDetailTutorial.StepTemplate] = [
            PostcardDetailTutorial.StepTemplate(
                highlightTarget: nil,
                normalizedRect: nil,
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Welcome to Postcard Detail",
                    cn: "歡迎來到明信片詳情頁"
                ),
                message: BilingualText(
                    en: "This page shows postcard details and buyer actions for placing or confirming an order.",
                    cn: "這裡會顯示明信片資訊，以及買家下單與收件確認的操作。"
                )
            ),
            PostcardDetailTutorial.StepTemplate(
                highlightTarget: .postcardDetailInfoSection,
                normalizedRect: CGRect(x: 0.04, y: 0.30, width: 0.92, height: 0.26),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Check title, price, and seller info",
                    cn: "先查看卡片名稱、價格與賣家資訊"
                ),
                message: BilingualText(
                    en: "Confirm postcard info and friend code before placing your order.",
                    cn: "下單前先確認卡片資訊與好友碼。"
                )
            ),
            PostcardDetailTutorial.StepTemplate(
                highlightTarget: .postcardBuyerBuyButton,
                normalizedRect: CGRect(x: 0.04, y: 0.76, width: 0.92, height: 0.08),
                messageBoxNormalizedY: 0.6,
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
        private static let listingTitle = BilingualText(en: "Riverside Lantern Card", cn: "河岸燈籠卡")
        /// Buyer tutorial fake listing country.
        private static let listingCountry = BilingualText(en: "US", cn: "US")
        /// Buyer tutorial fake listing province.
        private static let listingProvince = BilingualText(en: "San Francisco", cn: "舊金山")
        /// Buyer tutorial fake listing detail.
        private static let listingDetail = BilingualText(en: "Golden Gate Park", cn: "金門公園")
        /// Buyer tutorial fake seller name.
        private static let listingSellerName = BilingualText(en: "Host Lily", cn: "主持人 Lily")
    }

    /// Postcard detail tutorial in seller view.
    enum PostcardSeller {
        /// Replay postcard id used by tutorial catalog destination.
        static let replayPostcardId: String = "tutorial-postcard-seller"

        /// Active scenario selected for current language.
        static var scenario: PostcardDetailTutorial.Scenario {
            let language = TutorialConfig.currentLanguage
            return PostcardDetailTutorial.Scenario(
                steps: stepTemplates.map { step in
                    PostcardDetailTutorial.Step(
                        highlightTarget: step.highlightTarget,
                        normalizedRect: step.normalizedRect,
                        messageBoxNormalizedY: step.messageBoxNormalizedY,
                        title: step.title.value(for: language),
                        message: step.message.value(for: language)
                    )
                },
                fakeListing: PostcardListing(
                    id: replayPostcardId,
                    sellerId: "tutorial-postcard-seller-self",
                    title: listingTitle.value(for: language),
                    priceHoney: 90,
                    location: PostcardLocation(
                        country: listingCountry.value(for: language),
                        province: listingProvince.value(for: language),
                        detail: listingDetail.value(for: language)
                    ),
                    sellerName: listingSellerName.value(for: language),
                    sellerFriendCode: "222233334444",
                    stock: 3,
                    imageUrl: nil,
                    thumbnailUrl: nil,
                    createdAt: Date().addingTimeInterval(-1800)
                ),
                fakeBuyerOrderStatus: nil,
                fakePendingShippingCount: 2
            )
        }

        /// Shared step definitions with line-by-line bilingual text.
        private static let stepTemplates: [PostcardDetailTutorial.StepTemplate] = [
            PostcardDetailTutorial.StepTemplate(
                highlightTarget: nil,
                normalizedRect: nil,
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Welcome to Seller Postcard View",
                    cn: "歡迎來到賣家明信片頁"
                ),
                message: BilingualText(
                    en: "As a seller, you can manage shipping, share invite links, and edit listing info here.",
                    cn: "身為賣家，您可在此管理出貨、分享邀請連結並編輯卡片資訊。"
                )
            ),
            PostcardDetailTutorial.StepTemplate(
                highlightTarget: .postcardSellerShippingButton,
                normalizedRect: CGRect(x: 0.60, y: 0.04, width: 0.36, height: 0.08),
                messageBoxNormalizedY: 0.6,
                title: BilingualText(
                    en: "Seller toolbar actions",
                    cn: "賣家工具列功能"
                ),
                message: BilingualText(
                    en: "Share invite, open shipping queue, and edit listing from top-right actions.",
                    cn: "可從右上角快速分享邀請、查看出貨佇列與編輯卡片。"
                )
            ),
            PostcardDetailTutorial.StepTemplate(
                highlightTarget: .postcardDetailInfoSection,
                normalizedRect: CGRect(x: 0.04, y: 0.30, width: 0.92, height: 0.30),
                messageBoxNormalizedY: 0.6,
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
