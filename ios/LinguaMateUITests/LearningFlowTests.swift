import XCTest

final class LearningFlowTests: XCTestCase {
    @MainActor
    func testLocalLearningLoopAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing"]
        app.launch()
        let onboarding = app.buttons["finishOnboarding"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 10))
        for _ in 0..<6 where !onboarding.isHittable { app.swipeUp() }
        onboarding.tap()
        capture(app, name: "01-English-home")

        app.tabBars.buttons["对话"].tap()
        app.buttons["newConversation"].tap()
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("I am agree")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["What do you usually do after work or school?"].waitForExistence(timeout: 5))
        app.buttons["finishConversation"].tap()
        XCTAssertTrue(app.staticTexts["本轮反馈"].waitForExistence(timeout: 5))
        app.swipeUp()
        capture(app, name: "02-Local-conversation-feedback")

        app.tabBars.buttons["学习"].tap()
        app.buttons["startReview"].tap()
        app.buttons["revealWord"].tap()
        capture(app, name: "03-Vocabulary-review")
        app.buttons["rate-good"].tap()
        app.navigationBars.buttons["完成"].tap()

        app.tabBars.buttons["练习"].tap()
        app.buttons["practice-en-ielts-gardens-v1"].tap()
        for id in ["answer-gardens-1-1", "answer-gardens-2-0", "answer-gardens-3-2"] {
            let button = app.buttons[id]
            for _ in 0..<8 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable); button.tap()
        }
        let submit = app.buttons["submitPractice"]
        for _ in 0..<5 where !submit.isHittable { app.swipeUp() }
        submit.tap()
        XCTAssertTrue(app.staticTexts["practiceCompleted"].waitForExistence(timeout: 5))
        capture(app, name: "04-Practice-result")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertFalse(app.buttons["finishOnboarding"].exists)
        XCTAssertTrue(app.staticTexts["最近专项 · 城市花园与社区"].exists)
        app.segmentedControls["languagePicker"].buttons.element(boundBy: 1).tap()
        XCTAssertFalse(app.staticTexts["最近专项 · 城市花园与社区"].exists)
        capture(app, name: "05-Korean-home")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
