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
        // Ore pagate: si tolgono sempre almeno 11 minuti di pausa.
        XCTAssertEqual(Turno(id: "a", inizio: ora(19, 6), fine: ora(19, 14, 11)).ore, 8, accuracy: 0.0001)
        XCTAssertEqual(Turno(id: "a", inizio: ora(19, 6), fine: ora(19, 14), pausaMin: 10).ore, 469.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(Turno(id: "a", inizio: ora(19, 6), fine: ora(19, 15), pausaMin: 60).ore, 8, accuracy: 0.0001)
        let turni = [turno(19, 6, 14), turno(20, 14, 22), turno(27, 6, 14)]
        XCTAssertEqual(Calcoli.ore(turni, da: ora(19, 0), a: ora(26, 0)), 16 - 22.0 / 60, accuracy: 0.0001)
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

    func testSettimaneInteDaLunediADomenicaEKW() {
        let s = Calcoli.settimane(mese: ora(15, 12))
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.first, c.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        XCTAssertEqual(s.last, ora(26, 0))
        XCTAssertEqual(s.map(Calcoli.kw), [40, 41, 42, 43, 44])
    }

    // Settimana 19–25 ottobre 2026 (domenica 25).
    func settimana(_ fine: Int, domenica: Bool) -> [Turno] {
        var t = (19...23).map { Turno(id: "\($0)", inizio: ora($0, 6), fine: ora($0, fine)) }
        if domenica { t.append(Turno(id: "25", inizio: ora(25, 6), fine: ora(25, fine))) }
        return t
    }

    func testFNGServonoDomenicaE44OrePagate() {
        let lunedi = ora(19, 0)
        // 6 turni da 8h11m = 48 ore pagate, con la domenica: FNG.
        XCTAssertTrue(Calcoli.fng(settimana(14, domenica: true).map { var x = $0; x.fine = x.fine.addingTimeInterval(660); return x }, lunedi: lunedi))
        // 5 turni da 9h11m = 45 ore pagate ma senza domenica: niente FNG.
        XCTAssertFalse(Calcoli.fng(settimana(15, domenica: false).map { var x = $0; x.fine = x.fine.addingTimeInterval(660); return x }, lunedi: lunedi))
        // Con la domenica ma solo 5 turni da 8h (39h05m pagate): niente FNG.
        let poche = (19...22).map { Turno(id: "\($0)", inizio: ora($0, 6), fine: ora($0, 14)) } + [Turno(id: "25", inizio: ora(25, 6), fine: ora(25, 14))]
        XCTAssertFalse(Calcoli.fng(poche, lunedi: lunedi))
        // Esattamente 44 ore pagate con la domenica: FNG.
        let giuste = (19...22).map { Turno(id: "\($0)", inizio: ora($0, 6), fine: ora($0, 15, 11)) }
            + [Turno(id: "25", inizio: ora(25, 6), fine: ora(25, 14, 11))]
        XCTAssertEqual(Calcoli.ore(giuste, da: lunedi, a: ora(26, 0)), 44, accuracy: 0.0001)
        XCTAssertTrue(Calcoli.fng(giuste, lunedi: lunedi))
    }

    func testPausaFatta() {
        Pause.segna("prova", fatta: true)
        XCTAssertTrue(Pause.fatta("prova"))
        Pause.segna("prova", fatta: false)
        XCTAssertFalse(Pause.fatta("prova"))
    }

    func testCondivisioneTurnoEMemo() {
        let t = Turno(id: "a", inizio: ora(19, 6), fine: ora(19, 16), pausaMin: 30)
        let (letto, _) = Condivisione.leggi(note: Condivisione.noteTurno(t), titolo: Condivisione.titoloTurno(t),
                                           inizio: t.inizio, fine: t.fine, id: "x")
        XCTAssertEqual(letto?.pausa, 30)
        XCTAssertEqual(letto?.ore ?? 0, 9.5, accuracy: 0.0001)
        let (_, memo) = Condivisione.leggi(note: Condivisione.noteMemo(id: "m1", fatto: true), titolo: "Ritirare pacco",
                                          inizio: ora(19, 0), fine: ora(19, 23), id: "y")
        XCTAssertEqual(memo?.testo, "Ritirare pacco")
        XCTAssertEqual(memo?.fatto, true)
        // Gli eventi normali (es. Dayforce) non sono dell'app.
        let (n1, n2) = Condivisione.leggi(note: "Turno lavoro", titolo: "Lavoro", inizio: ora(19, 6), fine: ora(19, 14), id: "z")
        XCTAssertNil(n1); XCTAssertNil(n2)
        XCTAssertEqual(Condivisione.nome("Turni Salvo"), "Salvo")
    }

    func testOreInMinutiECentesimi() {
        XCTAssertEqual(oreMinuti(40 + 5.0 / 60), "40 h 5 min")
        XCTAssertEqual(centesimi(40 + 5.0 / 60), "40,08 h")
        XCTAssertEqual(oreMinuti(8), "8 h")
        XCTAssertEqual(oreMinuti(8 + 19.0 / 60), "8 h 19 min")
    }

    func testDoppioniTraDueCalendari() {
        let a = turno(19, 6, 14)
        var b = turno(19, 6, 14); b.id = "supershift"
        XCTAssertEqual(Calcoli.senzaDoppioni([a, b, turno(20, 14, 22)]).count, 2)
    }

    func testDueCalendariAccesiNonSiSommano() {
        // Prima Dayforce, poi SuperShift con gli stessi giorni (orari un po' diversi) e un calendario personale.
        let dayforce = [turno(19, 6, 14), turno(20, 14, 22)]
        let supershift = [Turno(id: "s1", inizio: ora(19, 6), fine: ora(19, 14, 11)), turno(21, 6, 14)]
        let personale = [Turno(id: "dentista", inizio: ora(22, 16), fine: ora(22, 17)),
                         Turno(id: "ferie", inizio: ora(23, 0), fine: ora(26, 0))]
        let turni = Calcoli.soloTurni(dayforce + supershift + personale)
        XCTAssertEqual(turni.map(\.id), ["19-6", "20-14", "21-6"])
    }

    func testTurnoDaConfermare() {
        let turni = [turno(18, 6, 14), turno(19, 5, 13)]
        // Durante il turno di oggi c'è da confermare quello di ieri.
        XCTAssertEqual(Conferme.daConfermare(turni, ora: ora(19, 10), confermato: { _ in false })?.id, "18-6")
        // Finito il turno di oggi, si chiede l'ultimo.
        XCTAssertEqual(Conferme.daConfermare(turni, ora: ora(19, 14), confermato: { _ in false })?.id, "19-5")
        // Confermati tutti e due: niente.
        XCTAssertNil(Conferme.daConfermare(turni, ora: ora(19, 14), confermato: { _ in true }))
        // Dopo 3 giorni non si chiede più.
        XCTAssertNil(Conferme.daConfermare([turno(10, 6, 14)], ora: ora(19, 14), confermato: { _ in false }))
    }

    func testBancaOre() {
        // Settimana 19–25 ottobre: 5 turni da 9h11m = 45 ore pagate → +5 h.
        let turni = (19...23).map { Turno(id: "\($0)", inizio: ora($0, 6), fine: ora($0, 15, 11)) }
        XCTAssertEqual(BancaOre.settimana(turni, lunedi: ora(19, 0)) ?? 0, 5, accuracy: 0.0001)
        // Settimana senza turni (ferie): non conta.
        XCTAssertNil(BancaOre.settimana(turni, lunedi: ora(12, 0)))
        // Il saldo conta solo le settimane finite.
        XCTAssertEqual(BancaOre.saldo(turni, da: ora(1, 0), a: ora(31, 0), ora: ora(24, 12)), 0, accuracy: 0.0001)
        XCTAssertEqual(BancaOre.saldo(turni, da: ora(1, 0), a: ora(31, 0), ora: ora(27, 12)), 5, accuracy: 0.0001)
    }

    func testCambiDiDayforce() {
        let prima = [turno(20, 6, 14), turno(21, 6, 14), turno(22, 14, 22)]
        let dopo = [turno(20, 6, 14), turno(21, 14, 22), turno(23, 6, 14)]
        let c = Calcoli.cambi(prima: prima, dopo: dopo, da: ora(20, 0))
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].prima?.id, "21-6"); XCTAssertEqual(c[0].dopo?.id, "21-14")   // cambiato
        XCTAssertNil(c[1].dopo)                                                         // tolto il 22
        XCTAssertNil(c[2].prima)                                                        // aggiunto il 23
        // I giorni passati non contano.
        XCTAssertTrue(Calcoli.cambi(prima: prima, dopo: dopo, da: ora(24, 0)).isEmpty)
    }

    func testStorico() {
        Storico.aggiungi("A mano", "Prova", "☀️ 06:00–13:30 → ☀️ 06:00–14:30")
        XCTAssertEqual(Storico.tutte().first?.titolo, "Prova")
        XCTAssertEqual(Storico.descrivi(nil), "😴 Riposo")
    }

    func testArchivioSalvaECarica() {
        let turni = [turno(19, 6, 14)]
        Archivio.salva(turni)
        XCTAssertEqual(Archivio.carica(), turni)
    }
}
