//
//  PostcardSeller.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines TutorialScene.PostcardSeller scenario data and step configuration.
//
import Foundation

extension TutorialScene {
enum PostcardSeller {
    /// Replay postcard id used by tutorial catalog destination.
    static let replayPostcardId: String = "tutorial-postcard-seller"

    /// Active scenario selected for current language.
    static var scenario: PostcardDetailTutorial.Scenario {
        return PostcardDetailTutorial.Scenario(
            steps: stepTemplates,
            fakeListing: TutorialScene.makeTutorialPostcardDetailListing(
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
                cn: "上架明信片教學"
            ),
            message: BilingualText(
                en: "As a seller, you can manage shipping, share invite links, and edit listing info here.",
                cn: "* 身為賣家，您可在此管理訂單、分享邀請連結並編輯卡片資訊"
            )
        ),
        PostcardDetailTutorial.Step(
            highlightTarget: .postcardDetailInfoSection,
            title: BilingualText(
                en: "Keep listing info accurate",
                cn: "明信片資訊"
            ),
            message: BilingualText(
                en: "Buyers rely on title, location, and stock shown in this section.",
                cn: "* 請確認ID跟好友碼與Pikmin一致"
            )
        ),
        PostcardDetailTutorial.Step(
            highlightTarget: .postcardSellerShareButton,
            title: BilingualText(
                en: "Seller toolbar actions",
                cn: "分享明信片"
            ),
            message: BilingualText(
                en: "Share invite, open shipping queue, and edit listing from top-right actions.",
                cn: "* 可以用二維碼將此上架明信片分享給親朋好友"
            )
        ),
        PostcardDetailTutorial.Step(
            highlightTarget: .postcardSellerShippingButton,
            title: BilingualText(
                en: "Seller toolbar actions",
                cn: "訂單管理"
            ),
            message: BilingualText(
                en: "Share invite, open shipping queue, and edit listing from top-right actions.",
                cn: "* 接受或拒絕訂單\n* 通知買家已出貨"
            )
        ),
        PostcardDetailTutorial.Step(
            highlightTarget: .postcardSellerEditButton,
            title: BilingualText(
                en: "Seller toolbar actions",
                cn: "變更明信片設定"
            ),
            message: BilingualText(
                en: "Share invite, open shipping queue, and edit listing from top-right actions.",
                cn: "* 更改明信片價格或資訊\n* 下架明信片"
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
}
