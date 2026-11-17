import XCTest

final class QuotaPieUITests: XCTestCase {
    @MainActor
    func testDarkEmptyState() throws {
        let app = XCUIApplication(bundleIdentifier: "zauli.med.QuotaPie")
        app.launchArguments = ["--ui-testing", "--ui-dark", "--ui-empty"]
        app.launch()
        let icon = app.descendants(matching: .any)["usageStatusItem"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        icon.hover()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Demonstração de dados indisponíveis."].firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Dark empty state"
        image.lifetime = .keepAlways
        add(image)
        // Moving below the panel must close it after the bridge tolerance.
        icon.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 0, dy: 900)).hover()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.buttons["openSettings"])
        waitForExpectations(timeout: 3)
        app.terminate()
    }

    @MainActor
    func testMenuBarPanelAndSettings() throws {
        let app = XCUIApplication(bundleIdentifier: "zauli.med.QuotaPie")
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let icon = app.descendants(matching: .any)["usageStatusItem"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "Ícone deve estar acessível na barra de menus.")
        icon.hover()
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "Hover deve abrir o painel.")
        settings.hover()
        XCTAssertTrue(settings.exists, "Painel deve permanecer durante interação.")
        XCTAssertFalse(app.staticTexts["ChatGPT"].exists)
        XCTAssertTrue(app.staticTexts["Codex"].exists)
        XCTAssertTrue(app.staticTexts["Claude"].exists)
        let panelImage = XCTAttachment(screenshot: app.screenshot())
        panelImage.name = "Dashboard"
        panelImage.lifetime = .keepAlways
        add(panelImage)
        settings.click()
        XCTAssertTrue(app.windows["AI Usage Monitor · Configurações"].waitForExistence(timeout: 3))
        app.windows["AI Usage Monitor · Configurações"].buttons[XCUIIdentifierCloseWindow].click()
        icon.click()
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "Clique deve abrir o painel.")
        app.terminate()
    }
}
