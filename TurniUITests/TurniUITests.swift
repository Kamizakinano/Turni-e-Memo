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
        app.tabBars.buttons["Turni"].tap()
        XCTAssertTrue(app.staticTexts["Portare il badge"].waitForExistence(timeout: 5))

        // Turno segnato a mano nel calendario
        app.tabBars.buttons["Turni"].tap()
        let giorno = Calendar.current.component(.day, from: .now)
        let cella = app.descendants(matching: .any)["giorno-\(giorno)"].firstMatch
        XCTAssertTrue(cella.waitForExistence(timeout: 5))
        cella.tap()
        let modifica = app.buttons["✏️ Turno"]
        XCTAssertTrue(modifica.waitForExistence(timeout: 5))
        if !modifica.isHittable { app.swipeUp() }
        modifica.tap()
        app.buttons["☀️ Mattina"].tap()
        app.buttons["Salva"].tap()
        app.tabBars.buttons["Turni"].tap()
        // Prima della fine del turno si vede la mattina, dopo c'è la conferma (il turno è già confermato perché segnato a mano).
        XCTAssertTrue(app.staticTexts["☀️ Mattina"].waitForExistence(timeout: 5) || app.staticTexts["✅ Fatto"].exists)
        app.tabBars.buttons["Turni"].tap()
        XCTAssertTrue(app.staticTexts["Ore per settimana"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Turni"].tap()

        app.tabBars.buttons["Ore"].tap()
        XCTAssertTrue(app.staticTexts["Ore"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Altro"].tap()
        XCTAssertTrue(app.navigationBars["Altro"].waitForExistence(timeout: 5))
    }
}
