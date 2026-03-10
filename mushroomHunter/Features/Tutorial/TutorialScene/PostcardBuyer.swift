//
//  PostcardBuyer.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines TutorialScene.PostcardBuyer scenario data and step configuration.
//
import Foundation

extension TutorialScene {
enum PostcardBuyer {
    /// Replay postcard id used by tutorial catalog destination.
    static let replayPostcardId: String = "tutorial-postcard-buyer"

    /// Active scenario selected for current language.
    static var scenario: PostcardDetailTutorial.Scenario {
        return PostcardDetailTutorial.Scenario(
            steps: stepTemplates,
            fakeListing: TutorialScene.makeTutorialPostcardDetailListing(
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
                cn: "* 購買明信片需要支付蜂蜜\n* 在Pikmin中加賣家好友後即可請賣家寄送明信片"
            )
        ),
        PostcardDetailTutorial.Step(
            highlightTarget: .postcardDetailInfoSection,
            title: BilingualText(
                en: "Check title, price, and seller info",
                cn: "明信片資訊"
            ),
            message: BilingualText(
                en: "Confirm postcard info and friend code before placing your order.",
                cn: "* 下單後請特別注意Pikmin中的賣家好友邀請"
            )
        ),
        PostcardDetailTutorial.Step(
            highlightTarget: .postcardBuyerBuyButton,
            title: BilingualText(
                en: "Check title, price, and seller info",
                cn: "購買明信片"
            ),
            message: BilingualText(
                en: "Confirm postcard info and friend code before placing your order.",
                cn: "* 下單後會直接扣除蜂蜜\n* 買家出貨後約12hr後明信片會送達"
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
