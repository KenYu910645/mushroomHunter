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
            /// Optional highlight rectangle in normalized screen coordinates. Nil means full-screen highlight.
            let normalizedRect: CGRect?
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
            /// Optional shared highlight rectangle for all languages. Nil means full-screen highlight.
            let normalizedRect: CGRect?
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
                        normalizedRect: step.normalizedRect,
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
                normalizedRect: nil,
                title: BilingualText(
                    en: "Welcome to Mushroom Browse",
                    cn: "歡迎來到蘑菇列表"
                ),
                message: BilingualText(
                    en: "This page helps you find raids quickly, check room status, and jump into your next run.",
                    cn: "這個頁面可快速找團、查看房間狀態，並快速加入下一場蘑菇挑戰。"
                )
            ),
            StepTemplate(
                normalizedRect: CGRect(x: 0.02, y: 0.20, width: 0.96, height: 0.09),
                title: BilingualText(
                    en: "This is your Mushroom browse list",
                    cn: "這裡是蘑菇列表頁"
                ),
                message: BilingualText(
                    en: "You can quickly see your honey, search rooms, and open create-room from the top bar.",
                    cn: "上方可查看蜂蜜、搜尋房間，並從右側建立新房間。"
                )
            ),
            StepTemplate(
                normalizedRect: CGRect(x: 0.02, y: 0.32, width: 0.96, height: 0.30),
                title: BilingualText(
                    en: "Owned rooms are pinned first",
                    cn: "您的房間會固定在前面"
                ),
                message: BilingualText(
                    en: "Rows tagged Host or Joined are your own rooms so you can return to them quickly.",
                    cn: "標示 Host 或 Joined 的列代表您的房間，方便快速回到常用房間。"
                )
            ),
            StepTemplate(
                normalizedRect: CGRect(x: 0.79, y: 0.20, width: 0.17, height: 0.09),
                title: BilingualText(
                    en: "Tap + to create your host room",
                    cn: "點 + 建立主持房間"
                ),
                message: BilingualText(
                    en: "Create room, set location and rules, then invite your Pikmin Bloom friends.",
                    cn: "建立房間後設定地點與規則，再邀請 Pikmin Bloom 朋友一起參加。"
                )
            )
        ]

        /// Shared fake room definitions with line-by-line bilingual text.
        private static let fakeRoomTemplates: [FakeRoomTemplate] = [
            FakeRoomTemplate(
                id: "tutorial-host",
                title: BilingualText(en: "Downtown Giant Mushroom", cn: "市中心巨大蘑菇"),
                mushroomType: BilingualText(en: "Fire", cn: "火"),
                joinedPlayers: 1,
                maxPlayers: 10,
                hostUid: "tutorial-host-uid",
                hostStars: 3,
                location: BilingualText(en: "US, New York", cn: "US, 紐約"),
                createdAtOffsetSeconds: -1800,
                lastSuccessfulRaidAtOffsetSeconds: -3600
            ),
            FakeRoomTemplate(
                id: "tutorial-joined",
                title: BilingualText(en: "Central Park Afternoon Raid", cn: "中央公園午後團"),
                mushroomType: BilingualText(en: "Water", cn: "水"),
                joinedPlayers: 4,
                maxPlayers: 10,
                hostUid: "tutorial-joined-host-uid",
                hostStars: 2,
                location: BilingualText(en: "US, New York", cn: "US, 紐約"),
                createdAtOffsetSeconds: -5400,
                lastSuccessfulRaidAtOffsetSeconds: -7200
            ),
            FakeRoomTemplate(
                id: "tutorial-general-1",
                title: BilingualText(en: "Quick Red Mushroom", cn: "快速紅菇團"),
                mushroomType: BilingualText(en: "Normal", cn: "普通"),
                joinedPlayers: 6,
                maxPlayers: 10,
                hostUid: "tutorial-general-host-1",
                hostStars: 1,
                location: BilingualText(en: "US, Boston", cn: "US, 波士頓"),
                createdAtOffsetSeconds: -10800,
                lastSuccessfulRaidAtOffsetSeconds: -10800
            ),
            FakeRoomTemplate(
                id: "tutorial-general-2",
                title: BilingualText(en: "Night Walk Squad", cn: "夜行散步團"),
                mushroomType: BilingualText(en: "Electric", cn: "電"),
                joinedPlayers: 2,
                maxPlayers: 10,
                hostUid: "tutorial-general-host-2",
                hostStars: 1,
                location: BilingualText(en: "US, Seattle", cn: "US, 西雅圖"),
                createdAtOffsetSeconds: -14400,
                lastSuccessfulRaidAtOffsetSeconds: -16000
            )
        ]

        /// Hosted room ids used for ownership badges.
        private static let hostRoomIds: Set<String> = ["tutorial-host"]
        /// Joined room ids used for ownership badges.
        private static let joinedRoomIds: Set<String> = ["tutorial-joined"]
    }
}
