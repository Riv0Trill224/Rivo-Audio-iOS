import XCTest

final class LaunchTests: XCTestCase {
    func testLibraryEqualizerAndTransfersOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Biblioteca"].waitForExistence(timeout: 15))
        app.tabBars.buttons["EQ"].tap()
        XCTAssertTrue(app.navigationBars["Ecualizador"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Ecualizador"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.tabBars.buttons["Transferir"].tap()
        XCTAssertTrue(app.navigationBars["Transferir"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Escuchas"].tap()
        XCTAssertTrue(app.navigationBars["Scrobbling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["API key"].exists)
        app.tabBars.buttons["Canciones"].tap()
        XCTAssertTrue(app.navigationBars["Biblioteca"].exists)
    }
}
