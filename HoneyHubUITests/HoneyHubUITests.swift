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
    func testHostFlowCanOpenAndFillRequiredFields() throws { // Handles testHostFlowCanOpenAndFillRequiredFields flow.
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--mock-rooms"]
        app.launch()

        let createButton = app.buttons["browse_create_button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.tap()

        let nameField = app.textFields["host_name_field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))

        let cityField = app.textFields["host_city_field"]
        XCTAssertTrue(cityField.waitForExistence(timeout: 10))

        let closeButton = app.buttons["host_close_button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testJoinFlowCanOpenRoomAndJoinFixture() throws { // Handles testJoinFlowCanOpenRoomAndJoinFixture flow.
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--mock-rooms"]
        app.launch()

        let quickJoinButton = app.buttons["browse_quick_join_button_ui-test-room-001"]
        XCTAssertTrue(quickJoinButton.waitForExistence(timeout: 10))
        quickJoinButton.tap()

        let joinAlert = app.alerts.firstMatch
        XCTAssertTrue(joinAlert.waitForExistence(timeout: 10))
        XCTAssertTrue(joinAlert.buttons.count >= 2)
    }
}
