import XCTest

final class TurniUITests: XCTestCase {
    func testSchedeMemoETurnoAMano() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Oggi"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Collega il calendario"].exists)

        // Nuovo memo
        app.tabBars.buttons["Memo"].tap()
        app.buttons["Nuovo memo"].tap()
        let campo = app.textFields["Cosa devi ricordare?"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText("Portare il badge")
        app.buttons["Salva"].tap()
        XCTAssertTrue(app.staticTexts["Portare il badge"].waitForExistence(timeout: 5))

        // Il memo compare in Oggi
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.staticTexts["Portare il badge"].waitForExistence(timeout: 5))

        // Turno segnato a mano nel calendario
        app.tabBars.buttons["Calendario"].tap()
        let giorno = Calendar.current.component(.day, from: .now)
        app.buttons["giorno-\(giorno)"].tap()
        app.buttons["☀️ Mattina"].tap()
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.staticTexts["☀️ Mattina"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Ore"].tap()
        XCTAssertTrue(app.staticTexts["Ore"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Altro"].tap()
        XCTAssertTrue(app.navigationBars["Altro"].waitForExistence(timeout: 5))
    }
}
