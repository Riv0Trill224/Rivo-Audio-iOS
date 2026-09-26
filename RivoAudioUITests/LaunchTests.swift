import XCTest

final class LaunchTests: XCTestCase {
    func testPlayerLayoutAndControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Neon Nights").firstMatch.waitForExistence(timeout: 15))
        app.buttons.containing(.staticText, identifier: "Neon Nights").firstMatch.tap()
        XCTAssertTrue(app.buttons["Cerrar reproductor"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reproductor-v013"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.sliders["Posición de reproducción"].exists)
        app.buttons["Cerrar reproductor"].tap()
        app.tabBars.buttons["EQ"].tap()
        XCTAssertTrue(app.navigationBars["Ecualizador"].waitForExistence(timeout: 5))
        let eq = XCTAttachment(screenshot: app.screenshot())
        eq.name = "EQ-v013"; eq.lifetime = .keepAlways; add(eq)
    }
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
