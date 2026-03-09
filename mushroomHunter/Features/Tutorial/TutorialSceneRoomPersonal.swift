//
//  TutorialSceneRoomPersonal.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines TutorialScene.RoomPersonal scenario data and step configuration.
//
import Foundation

extension TutorialScene {
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

}
