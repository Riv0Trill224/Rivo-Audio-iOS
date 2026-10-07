import XCTest
final class LaunchTests: XCTestCase {
    func testTabsAndEmptyLibraryOnIPhone13() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Seleccionar carpeta"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Automatizar"].tap()
        XCTAssertTrue(app.staticTexts["Completa tu biblioteca"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Pendientes"].tap()
        XCTAssertTrue(app.staticTexts["No hay coincidencias pendientes"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Ajustes"].tap()
        XCTAssertTrue(app.staticTexts["Rivo Metadata Editor · 0.1.0"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Rivo Metadata Editor · iPhone 13"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
