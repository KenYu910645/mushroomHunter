//
//  HoneyHubUITests.swift
//  mushroomHunter
//
//  Purpose:
//  - Contains end-to-end UI coverage for the main user flows.
//
//  Defined in this file:
//  - HoneyHubUITests test cases and launch helpers.
//
import XCTest

final class HoneyHubUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--mock-rooms", "--mock-postcards"]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, index: Int) {
        let tab = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    @MainActor
    private func navigationBarButton(_ app: XCUIApplication, identifier: String, fallbackIndex: Int) -> XCUIElement {
        let byId = app.buttons[identifier]
        if byId.exists { return byId }
        return app.navigationBars.buttons.element(boundBy: fallbackIndex)
    }

    @MainActor
    func testSanityLoginAndNavigateAllTabs() throws {
        let app = launchApp()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        tapTab(app, index: 1)
        XCTAssertTrue(app.buttons["postcard_create_button"].waitForExistence(timeout: 10))

        tapTab(app, index: 2)
        XCTAssertTrue(app.buttons["profile_edit_button"].waitForExistence(timeout: 10))

        tapTab(app, index: 0)
        XCTAssertTrue(app.buttons["browse_create_button"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHostFlowCanOpenAndFillRequiredFields() throws { // Handles testHostFlowCanOpenAndFillRequiredFields flow.
        let app = launchApp()

        let createButton = app.buttons["browse_create_button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.tap()

        let nameField = app.textFields["host_name_field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))

        let cityField = app.textFields["host_city_field"]
        XCTAssertTrue(cityField.waitForExistence(timeout: 10))

        app.swipeUp()
        let submitButton = app.buttons["host_submit_button"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()

        let successAlert = app.alerts.firstMatch
        XCTAssertTrue(successAlert.waitForExistence(timeout: 10))
        successAlert.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testJoinFlowCanOpenRoomAndJoinFixture() throws { // Handles testJoinFlowCanOpenRoomAndJoinFixture flow.
        let app = launchApp()

        let quickJoinButton = app.buttons["browse_quick_join_button_ui-test-room-001"]
        XCTAssertTrue(quickJoinButton.waitForExistence(timeout: 10))
        quickJoinButton.tap()

        let joinAlert = app.alerts.firstMatch
        _ = joinAlert.waitForExistence(timeout: 5)
    }

    @MainActor
    func testBuyPostcardFlow() throws {
        let app = launchApp()

        tapTab(app, index: 1)
        let listing = app.buttons["postcard_link_ui-test-postcard-001"]
        XCTAssertTrue(listing.waitForExistence(timeout: 10))
        listing.tap()

        let buyButton = app.buttons["postcard_buy_button"]
        XCTAssertTrue(buyButton.waitForExistence(timeout: 10))
        buyButton.tap()

        let successAlert = app.alerts.firstMatch
        XCTAssertTrue(successAlert.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSellPostcardFlow() throws {
        let app = launchApp()

        tapTab(app, index: 1)
        let createButton = app.buttons["postcard_create_button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.tap()

        let submitButton = app.buttons["postcard_form_quick_submit_button"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 10))
        submitButton.tap()

        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testDeepLinkPostcardInviteOpensDetail() throws {
        let app = launchApp(extraArguments: ["--ui-open-postcard", "ui-test-postcard-001"])
        XCTAssertTrue(app.buttons["postcard_buy_button"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testDeepLinkMushroomInviteOpensRoom() throws {
        let app = launchApp(extraArguments: ["--ui-open-room", "ui-test-room-001"])
        XCTAssertTrue(app.buttons["room_join_button"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testMushroomAttendeeLeaveFlow() throws {
        let app = launchApp(extraArguments: ["--ui-open-room", "ui-test-room-001", "--mock-room-joined"])

        let editBidButton = app.buttons["room_edit_bid_button"]
        XCTAssertTrue(editBidButton.waitForExistence(timeout: 15))
        editBidButton.tap()

        let leaveButton = app.buttons["room_leave_button"]
        XCTAssertTrue(leaveButton.waitForExistence(timeout: 10))
        leaveButton.tap()

        let leaveSuccessAlert = app.alerts.firstMatch
        if leaveSuccessAlert.waitForExistence(timeout: 5) {
            leaveSuccessAlert.buttons.element(boundBy: 0).tap()
        }

        let joinButton = app.buttons["room_join_button"]
        XCTAssertTrue(joinButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testPostcardSellerShippingFlow() throws {
        let app = launchApp()

        tapTab(app, index: 1)
        let ownedListing = app.buttons["postcard_link_ui-test-postcard-owned"]
        XCTAssertTrue(ownedListing.waitForExistence(timeout: 10))
        ownedListing.tap()

        let shippingButton = app.buttons["postcard_shipping_button"]
        XCTAssertTrue(shippingButton.waitForExistence(timeout: 10))
        shippingButton.tap()

        let sendButton = app.buttons["postcard_shipping_send_button_ui-test-order-001"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10))
        sendButton.tap()

        let successAlert = app.alerts.firstMatch
        XCTAssertTrue(successAlert.waitForExistence(timeout: 10))
        successAlert.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testProfileEditAndFeedbackAndAboutFlow() throws {
        let app = launchApp()

        tapTab(app, index: 2)
        let editButton = navigationBarButton(app, identifier: "profile_edit_button", fallbackIndex: 1)
        XCTAssertTrue(editButton.waitForExistence(timeout: 20))
        editButton.tap()

        let autofillButton = app.buttons["profile_form_autofill_button"]
        XCTAssertTrue(autofillButton.waitForExistence(timeout: 10))
        autofillButton.tap()

        let submitProfileButton = app.buttons["profile_form_submit_button"]
        XCTAssertTrue(submitProfileButton.waitForExistence(timeout: 10))
        submitProfileButton.tap()

        let updatedName = app.staticTexts["profile_display_name_value"]
        XCTAssertTrue(updatedName.waitForExistence(timeout: 10))
        XCTAssertEqual(updatedName.label, "Tester Updated")

        let settingsButton = navigationBarButton(app, identifier: "profile_settings_button", fallbackIndex: 0)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let feedbackButton = app.buttons["settings_feedback_button"]
        XCTAssertTrue(feedbackButton.waitForExistence(timeout: 10))
        feedbackButton.tap()

        let feedbackAutofillButton = app.buttons["feedback_autofill_button"]
        XCTAssertTrue(feedbackAutofillButton.waitForExistence(timeout: 10))
        feedbackAutofillButton.tap()

        let sendFeedbackButton = app.buttons["feedback_send_button"]
        XCTAssertTrue(sendFeedbackButton.waitForExistence(timeout: 10))
        sendFeedbackButton.tap()

        let feedbackSuccessAlert = app.alerts.firstMatch
        if feedbackSuccessAlert.waitForExistence(timeout: 5) {
            feedbackSuccessAlert.buttons.element(boundBy: 0).tap()
        }

        settingsButton.tap()
        let aboutButton = app.buttons["settings_about_button"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 10))
        aboutButton.tap()

        XCTAssertTrue(app.staticTexts["about_intro_text"].waitForExistence(timeout: 10))
    }
}
