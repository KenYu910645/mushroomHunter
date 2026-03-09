//
//  TutorialSceneRoomHost.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines TutorialScene.RoomHost scenario data and step configuration.
//
import Foundation

extension TutorialScene {
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
}
