//
//  TutorialScenePostcardBrowse.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines TutorialScene.PostcardBrowse scenario data and step configuration.
//
import Foundation

extension TutorialScene {
enum PostcardBrowse {
    /// Shared step shape alias used by postcard browse tutorial views.
    typealias Step = TutorialScene.Step

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
        let language = TutorialScene.currentLanguage
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
                cn: "* 用蜂蜜買賣Pikmin 明信片"
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
                cn: "* 搜尋明信片標題"
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
                cn: "置頂明信片"
            ),
            message: BilingualText(
                en: "On-shelf and Ordered cards are pinned first so you can track your own trading state.",
                cn: "* 已上架與已下單的明信片會置頂以方便查看"
            )
        ),
        Step(
            highlightTarget: .postcardBrowseGeneralListingsArea,
            title: BilingualText(
                en: "Pinned ownership cards",
                cn: "明信片資訊"
            ),
            message: BilingualText(
                en: "On-shelf and Ordered cards are pinned first so you can track your own trading state.",
                cn: "* 販賣價格在右上角"
            )
        )
    ]

    /// Shared fake listing definitions with line-by-line bilingual text.
    private static let listingTemplates: [FakeListing] = [
        FakeListing(
            id: replayPostcardId,
            title: BilingualText(en: "Central Park Pikmin Card", cn: "頂天立地小嬰兒"),
            priceHoney: 5,
            country: BilingualText(en: "US", cn: "台灣"),
            province: BilingualText(en: "New York", cn: "沙鹿"),
            detail: BilingualText(en: "Near lake area", cn: "鄉下地方"),
            sellerId: "tutorial-postcard-self-seller",
            sellerName: BilingualText(en: "You", cn: "小美"),
            sellerFriendCode: "222233334444",
            stock: 2,
            createdAtOffsetSeconds: -1200
        ),
        FakeListing(
            id: "tutorial-postcard-ordered",
            title: BilingualText(en: "Downtown Night Event Card", cn: "可愛河馬"),
            priceHoney: 10,
            country: BilingualText(en: "US", cn: "台灣"),
            province: BilingualText(en: "Seattle", cn: "桃園八德"),
            detail: BilingualText(en: "Space Needle", cn: "太空針塔"),
            sellerId: "tutorial-postcard-seller-2",
            sellerName: BilingualText(en: "Nina", cn: "小紫"),
            sellerFriendCode: "111122223333",
            stock: 1,
            createdAtOffsetSeconds: -2800
        ),
        FakeListing(
            id: "tutorial-postcard-general-1",
            title: BilingualText(en: "Harbor Sunrise Card", cn: "巨大皮克敏"),
            priceHoney: 50,
            country: BilingualText(en: "US", cn: "台灣"),
            province: BilingualText(en: "Boston", cn: "大安區"),
            detail: BilingualText(en: "", cn: ""),
            sellerId: "tutorial-postcard-seller-3",
            sellerName: BilingualText(en: "Ming", cn: "小明"),
            sellerFriendCode: "555566667777",
            stock: 3,
            createdAtOffsetSeconds: -4800
        ),
        FakeListing(
            id: "tutorial-postcard-general-2",
            title: BilingualText(en: "Rainy Day Station Card", cn: "養鴨人家"),
            priceHoney: 5,
            country: BilingualText(en: "US", cn: "台灣"),
            province: BilingualText(en: "Chicago", cn: "桃園"),
            detail: BilingualText(en: "", cn: ""),
            sellerId: "tutorial-postcard-seller-4",
            sellerName: BilingualText(en: "Alex", cn: "小安"),
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
}
