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

    func testFullscreenVideoRotatesBothLandscapeDirections() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--ui-video-fixture"]
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Video de prueba").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.buttons["Pantalla completa"].waitForExistence(timeout: 15))
        app.buttons["Pantalla completa"].tap()
        let wide = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: wide, evaluatedWith: nil); waitForExpectations(timeout: 10)
        let hidden = NSPredicate { _, _ in !app.buttons["Cerrar"].exists && !app.sliders["Posición del video"].exists }
        expectation(for: hidden, evaluatedWith: nil); waitForExpectations(timeout: 8)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 3))
        app.buttons["Pausar"].tap()
        XCTAssertTrue(app.buttons["Reproducir"].waitForExistence(timeout: 3))
        for direction in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = direction
            expectation(for: wide, evaluatedWith: nil); waitForExpectations(timeout: 10)
            if !app.buttons["Cerrar"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 3))
        }
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Landscape-video-v040"; image.lifetime = .keepAlways; add(image)
        if !app.buttons["Cerrar"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["Cerrar"].tap()
        let tall = NSPredicate { _, _ in app.frame.height > app.frame.width }
        expectation(for: tall, evaluatedWith: nil); waitForExpectations(timeout: 10)
        XCUIDevice.shared.orientation = .portrait
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
        XCTAssertTrue(app.tabBars.buttons["Ajustes"].waitForExistence(timeout: 5))
        let library = XCTAttachment(screenshot: app.screenshot())
        library.name = "Biblioteca-v013"; library.lifetime = .keepAlways; add(library)
        app.tabBars.buttons["Ajustes"].tap()
        app.buttons["Ecualizador"].tap()
        XCTAssertTrue(app.navigationBars["Ecualizador"].waitForExistence(timeout: 5))
        let eq = XCTAttachment(screenshot: app.screenshot())
        eq.name = "EQ-v013"; eq.lifetime = .keepAlways; add(eq)
    }
    func testLibraryAlbumsAndSettingsOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Inicio"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Biblioteca"].tap()
        let hub = XCTAttachment(screenshot: app.screenshot())
        hub.name = "Biblioteca-iPhone13-v040"; hub.lifetime = .keepAlways; add(hub)
        app.buttons["library-Álbumes"].tap()
        XCTAssertTrue(app.navigationBars["Álbumes"].waitForExistence(timeout: 5))
        let grid = XCTAttachment(screenshot: app.screenshot())
        grid.name = "Albums-grid-iPhone13-v040"; grid.lifetime = .keepAlways; add(grid)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "album-")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Álbum"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Album-iPhone13-v040"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["Ajustes"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 5))
        for _ in 0..<8 { if app.buttons["Acerca de"].isHittable { break }; app.swipeUp() }
        app.buttons["Acerca de"].tap()
        XCTAssertTrue(app.navigationBars["Acerca de"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Desarrollado por @Riv0Trill224"].exists)
    }
}
