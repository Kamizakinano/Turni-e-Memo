import XCTest
@testable import Turni

final class CalcoliTests: XCTestCase {
    let c = Calendar.current

    func ora(_ giorno: Int, _ h: Int, _ m: Int = 0) -> Date {
        c.date(from: DateComponents(year: 2026, month: 10, day: giorno, hour: h, minute: m))!
    }

    func turno(_ g: Int, _ da: Int, _ a: Int, manuale: Bool = false) -> Turno {
        Turno(id: "\(g)-\(da)", inizio: ora(g, da), fine: ora(g, a), manuale: manuale)
    }

    func testTipoDallOraDiInizio() {
        XCTAssertEqual(turno(19, 6, 14).tipo, .mattina)
        XCTAssertEqual(Turno(id: "a", inizio: ora(19, 11, 30), fine: ora(19, 19)).tipo, .mattina)
        XCTAssertEqual(turno(19, 12, 20).tipo, .pomeriggio)
        XCTAssertEqual(turno(19, 14, 22).tipo, .pomeriggio)
    }

    func testOre() {
        XCTAssertEqual(Turno(id: "a", inizio: ora(19, 6), fine: ora(19, 14, 30)).ore, 8.5)
        let turni = [turno(19, 6, 14), turno(20, 14, 22), turno(27, 6, 14)]
        XCTAssertEqual(Calcoli.ore(turni, da: ora(19, 0), a: ora(26, 0)), 16)
    }

    func testInCorsoProssimoEDomani() {
        let turni = [turno(19, 6, 14), turno(20, 14, 22)]
        XCTAssertEqual(Calcoli.inCorso(turni, ora: ora(19, 10))?.id, "19-6")
        XCTAssertNil(Calcoli.inCorso(turni, ora: ora(19, 14)))
        XCTAssertEqual(Calcoli.prossimo(turni, dopo: ora(19, 10))?.id, "20-14")
        XCTAssertEqual(Calcoli.domani(turni, ora: ora(19, 10))?.id, "20-14")
        XCTAssertNil(Calcoli.domani(turni, ora: ora(20, 10)))
    }

    func testIlTurnoSegnatoAManoVinceSuDayforce() {
        let cal = [turno(19, 6, 14), turno(20, 14, 22), turno(21, 6, 14)]
        let manuali = [turno(20, 6, 14, manuale: true)]
        let tutti = Calcoli.unisci(dalCalendario: cal, manuali: manuali, riposi: [ora(21, 0)])
        XCTAssertEqual(tutti.map(\.id), ["19-6", "20-6"])
        XCTAssertTrue(tutti[1].manuale)
    }

    func testContoAllaRovesciaSoloVicinoAlTurno() {
        let turni = [turno(20, 14, 22)]
        XCTAssertNil(ContoAllaRovescia.daMostrare(turni, ora: ora(20, 10)))
        XCTAssertEqual(ContoAllaRovescia.daMostrare(turni, ora: ora(20, 11, 30))?.id, "20-14")
        XCTAssertEqual(ContoAllaRovescia.daMostrare(turni, ora: ora(20, 21))?.id, "20-14")
        XCTAssertNil(ContoAllaRovescia.daMostrare(turni, ora: ora(20, 22)))
    }

    func testSettimanaPartedaLunedi() {
        XCTAssertEqual(Calcoli.inizioSettimana(ora(22, 15)), ora(19, 0))
        XCTAssertEqual(Calcoli.inizioSettimana(ora(25, 23)), ora(19, 0))
    }

    func testArchivioSalvaECarica() {
        let turni = [turno(19, 6, 14)]
        Archivio.salva(turni)
        XCTAssertEqual(Archivio.carica(), turni)
    }
}
