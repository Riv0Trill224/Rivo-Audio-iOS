import XCTest

final class LaunchTests: XCTestCase {
    func testIPhone13LongTitleAndArtworkStayWithinScreen() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--ui-long-metadata"]
        app.launch()
        let title = "Peso [Prod. By ASAP Ty Beats] — Extended title for narrow screens"
        let row = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar reproductor"].waitForExistence(timeout: 10))
        let artwork = app.descendants(matching: .any)["playerArtwork"].firstMatch
        let loaded = expectation(for: NSPredicate(format: "label == %@", "Carátula del álbum"), evaluatedWith: artwork)
        wait(for: [loaded], timeout: 10)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone13-390x844-long-title-with-artwork"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(app.frame.width, 390, accuracy: 1)
        XCTAssertEqual(app.frame.height, 844, accuracy: 1)
        let heading = app.staticTexts["playerTitle"]
        let artist = app.staticTexts["playerArtist"]
        let album = app.staticTexts["playerAlbum"]
        for element in [heading, artist, album, app.buttons["Cerrar reproductor"], app.buttons["Opciones de canción"]] {
            XCTAssertTrue(element.exists)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX + 23)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX - 23)
        }
        XCTAssertEqual(heading.frame.minX, artist.frame.minX, accuracy: 1)
        XCTAssertEqual(heading.frame.minX, album.frame.minX, accuracy: 1)
    }

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
        let output = app.descendants(matching: .any)["outputDevice"].firstMatch
        XCTAssertTrue(output.exists)
        XCTAssertLessThanOrEqual(output.frame.maxY, app.frame.maxY - 20)
        XCTAssertLessThanOrEqual(app.buttons["Cola"].frame.maxY, app.frame.maxY - 10)
        app.buttons["Cerrar reproductor"].tap()
        XCTAssertTrue(app.tabBars.buttons["EQ"].waitForExistence(timeout: 5))
        let library = XCTAttachment(screenshot: app.screenshot())
        library.name = "Biblioteca-v013"; library.lifetime = .keepAlways; add(library)
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
        app.tabBars.buttons["Ajustes"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Escuchas"].tap()
        XCTAssertTrue(app.navigationBars["Scrobbling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["API key"].exists)
        app.tabBars.buttons["Biblioteca"].tap()
        XCTAssertTrue(app.navigationBars["Biblioteca"].exists)
    }
}
