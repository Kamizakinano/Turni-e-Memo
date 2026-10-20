import XCTest
@testable import Turni

final class SuperShiftTests: XCTestCase {
    let c = Calendar.current

    func data(_ a: Int, _ m: Int, _ g: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: a, month: m, day: g, hour: h, minute: min))!
    }

    // Come esce dal PDF con le colonne in fila.
    let ordinato = """
                novembre 2025
                Giorno                      Ora               Pausa                        Titolo                  Luogo               Note
                         1       Sab   MA   05 20 - 14 29     11 00, 15 min   8 h 54 min   Mattina
                                            Tutto il giorno                                Ognissanti
                                            05 00 - 14 00                                  Commesso Specializzato
                     4           Mar   RI   00 00 - 00 00                     24 h         Riposo
                     6           Gio   MA   09 27 - 14 08                     4 h 41 min   Mattina
                                            05 30 - 12 00                                  Commesso Specializzato
                     8           Sab   PO   13 00 - 21 35     15 00, 22 min   8 h 13 min   Pomeriggio
                                            12 00 - 13 00                                  Vale Fiera
                dicembre 2025
                    25           Gio   FE   00 00 - 08 00                     8h           Festivita Casa
                                            Tutto il giorno                                Natale di Gesù
                    27           Sab   RI   00 00 - 00 00                     24 h         Riposo
                                            Tutto il giorno                                Istanbul
                                            09 00 - 15 00                     6h           FERIE
                    30           Mar   MA   06 00 - 14 22     11 00, 22 min   8h           Mattina
    """

    // Come esce con i pezzi in ordine diverso ("05", ":", "20", pausa dopo le ore).
    let sparso = """
    novembre 2025
    Giorno Titolo
    1 Sab MA 05
    :
    20 - 14
    :
    29 8 h 54 min Mattina
    11
    :
    00, 15 min
    Tutto il giorno Ognissanti
    05
    :
    00 - 14
    :
    00 Commesso Specializzato
    2 Dom MA 06
    :
    00 - 14
    :
    17 8 h 4 min Mattina
    11
    :
    00, 13 min
    """

    func testLeggeIlPDFOrdinato() {
        let g = SuperShift.leggi(ordinato)
        XCTAssertEqual(g.map(\.codice), ["MA", "RI", "MA", "PO", "FE", "RI", "MA"])
        XCTAssertEqual(g[0].giorno, data(2025, 11, 1))
        XCTAssertEqual(g[0].inizio, data(2025, 11, 1, 5, 20))
        XCTAssertEqual(g[0].fine, data(2025, 11, 1, 14, 29))
        XCTAssertEqual(g[0].pausa, 15)
        XCTAssertEqual(g[0].ore, 8 + 54.0 / 60, accuracy: 0.0001)
        XCTAssertTrue(g[1].riposo)
        XCTAssertNil(g[2].pausa)
        XCTAssertEqual(g[2].ore, 4 + 41.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(g[3].inizio, data(2025, 11, 8, 13, 0))
        XCTAssertEqual(g[4].giorno, data(2025, 12, 25))
        XCTAssertEqual(g[4].ore, 8)
        XCTAssertEqual(g[6].ore, 8)
    }

    func testNoteDiventanoMemoSenzaIlTurnoDiDayforce() {
        let g = SuperShift.leggi(ordinato)
        XCTAssertEqual(g[0].memo.map(\.testo), [])                       // solo "Commesso Specializzato"
        XCTAssertEqual(g[3].memo.map(\.testo), ["Vale Fiera"])
        XCTAssertEqual(g[3].memo.first?.ora, data(2025, 11, 8, 12, 0))
        // Le festività non diventano memo; le note di tutto il giorno e quelle dopo le ore ("6h FERIE") sì.
        XCTAssertEqual(g[4].memo.map(\.testo), [])
        XCTAssertEqual(Set(g[5].memo.map(\.testo)), ["FERIE", "Istanbul"])
        XCTAssertTrue(g[5].ferie)
        XCTAssertNil(g[5].memo.first { $0.testo == "Istanbul" }?.ora)
    }

    func testLeggeIlPDFSparso() {
        let g = SuperShift.leggi(sparso)
        XCTAssertEqual(g.count, 2)
        XCTAssertEqual(g[0].inizio, data(2025, 11, 1, 5, 20))
        XCTAssertEqual(g[0].fine, data(2025, 11, 1, 14, 29))
        XCTAssertEqual(g[0].pausa, 15)
        XCTAssertEqual(g[1].fine, data(2025, 11, 2, 14, 17))
        XCTAssertEqual(g[1].ore, 8 + 4.0 / 60, accuracy: 0.0001)
    }

    func testOrePagateImportateValgonoSulCalcolo() {
        let t = Turno(id: "x", inizio: data(2025, 11, 1, 5, 20), fine: data(2025, 11, 1, 14, 29), pausaMin: 15,
                      orePagate: 8 + 54.0 / 60, codice: "MA")
        XCTAssertEqual(oreMinuti(t.ore), "8 h 54 min")
        XCTAssertTrue(Turno(id: "f", inizio: .now, fine: .now, codice: "FE").assenza)
    }

    // Il testo vero del PDF di SuperShift (nov 2025 – ott 2026) con le note sostituite da "Nota 1", "Nota 2"…
    // e senza nomi né luoghi: ogni nota deve diventare un memo, e il turno previsto di Dayforce no.
    func testPDFVeroAnonimo() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "supershift-anonimo", withExtension: "txt"))
        let testo = try String(contentsOf: url, encoding: .utf8)
        let giorni = SuperShift.leggi(testo)
        XCTAssertEqual(giorni.count, 365)                                   // tutto l'anno, anche ferie ("g") e formazione ("h")
        XCTAssertEqual(giorni.filter { $0.codice == "FER" }.count, 30)
        XCTAssertEqual(giorni.filter { $0.codice == "FO" }.count, 3)
        let re = try NSRegularExpression(pattern: "Nota \\d+")
        let ns = testo as NSString
        let attese = Set(re.matches(in: testo, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
        let lette = Set(giorni.flatMap(\.memo).map(\.testo)).filter { $0.hasPrefix("Nota") }
        XCTAssertEqual(lette, attese, "Memo mancanti: \(attese.subtracting(lette).sorted())")
        XCTAssertFalse(giorni.flatMap(\.memo).contains { $0.testo == "Lavoro Previsto" })
        XCTAssertFalse(giorni.flatMap(\.memo).contains { $0.testo == "Ognissanti" })
        XCTAssertFalse(giorni.contains { $0.codice.first?.isLowercase == true })
    }
}
