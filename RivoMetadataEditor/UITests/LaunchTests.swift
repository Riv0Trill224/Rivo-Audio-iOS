import XCTest
final class LaunchTests: XCTestCase {
    func testTabsAndEmptyLibraryOnIPhone13() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Seleccionar carpeta"].waitForExistence(timeout: 30))
        let automationTab = app.tabBars.buttons["Automatizar"]
        automationTab.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: automationTab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 15), .completed)
        XCTAssertTrue(app.switches["genius-verification"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Pendientes"].tap()
        XCTAssertTrue(app.staticTexts["No hay coincidencias pendientes"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Ajustes"].tap()
        let tokenField = app.secureTextFields["Client Access Token"]
        for _ in 0..<4 { if tokenField.exists { break }; app.swipeUp() }
        XCTAssertTrue(tokenField.waitForExistence(timeout: 3))
        let version = app.staticTexts["Rivo Metadata Editor · 0.2.0"]
        for _ in 0..<5 { if version.exists { break }; app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Rivo Metadata Editor · iPhone 13"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
