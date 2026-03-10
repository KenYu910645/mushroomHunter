//
//  RoomBrowse.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines TutorialScene.RoomBrowse scenario data and step configuration.
//
import Foundation

extension TutorialScene {
enum RoomBrowse {
    /// Shared step shape alias used by Mushroom browse tutorial views.
    typealias Step = TutorialScene.Step
    /// Shared fake-room shape alias used by Mushroom browse tutorial scenes.
    typealias FakeRoom = TutorialScene.BrowseFakeRoom

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
                cn: "* 打蘑菇需要消耗蜂蜜"
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
}
