import Foundation
import EventKit

// Condivisione con un'altra persona tramite un calendario iCloud "Turni <nome>".
// La tua app ci scrive turni e/o memo; l'altra persona lo riceve condiviso (solo lettura) e la sua app lo legge.

struct MemoCondiviso: Hashable, Identifiable {
    var id: String
    var testo: String
    var giorno: Date
    var fatto: Bool
}

struct Persona: Hashable, Identifiable {
    var id: String          // id del calendario
    var nome: String
    var turni: [Turno]
    var memo: [MemoCondiviso]
}

enum Condivisione {
    static let segno = "TURNI-APP"
    static let prefisso = "Turni "

    static func èDellApp(_ e: EKEvent) -> Bool { e.notes?.hasPrefix(segno) == true }

    /// Il nome della persona dal titolo del calendario ("Turni Salvo" → "Salvo").
    static func nome(_ titolo: String) -> String {
        titolo.hasPrefix(prefisso) ? String(titolo.dropFirst(prefisso.count)) : titolo
    }

    // Testo nelle note dell'evento: "TURNI-APP|T|<pausa>" per un turno, "TURNI-APP|M|<id>|<0/1>" per un memo.
    static func noteTurno(_ t: Turno) -> String { "\(segno)|T|\(t.pausa)" }
    static func noteMemo(id: String, fatto: Bool) -> String { "\(segno)|M|\(id)|\(fatto ? 1 : 0)" }

    static func titoloTurno(_ t: Turno) -> String { "\(t.tipo.emoji) \(t.tipo.nome) \(t.orario)" }

    /// Legge un evento scritto dall'app: un turno o un memo.
    static func leggi(note: String, titolo: String, inizio: Date, fine: Date, id: String) -> (Turno?, MemoCondiviso?) {
        let parti = note.split(separator: "|").map(String.init)
        guard parti.count >= 2, parti[0] == segno else { return (nil, nil) }
        if parti[1] == "T" {
            let pausa = parti.count > 2 ? Int(parti[2]) : nil
            return (Turno(id: id, inizio: inizio, fine: fine, pausaMin: pausa), nil)
        }
        if parti[1] == "M", parti.count >= 4 {
            return (nil, MemoCondiviso(id: parti[2], testo: titolo, giorno: Calendar.current.startOfDay(for: inizio), fatto: parti[3] == "1"))
        }
        return (nil, nil)
    }
}

extension Stato {
    var calendarioMio: EKCalendar? {
        guard let id = UserDefaults.standard.string(forKey: "calendarioCondiviso") else { return nil }
        return store.calendar(withIdentifier: id)
    }

    /// I calendari "Turni …" che non sono il tuo: quelli che altre persone condividono con te.
    var calendariDiAltri: [EKCalendar] {
        guard accesso else { return [] }
        let mio = UserDefaults.standard.string(forKey: "calendarioCondiviso")
        return store.calendars(for: .event)
            .filter { $0.title.hasPrefix(Condivisione.prefisso) && $0.calendarIdentifier != mio }
            .sorted { $0.title < $1.title }
    }

    var seguiti: [String] {
        get { UserDefaults.standard.stringArray(forKey: "seguiti") ?? [] }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "seguiti"); leggiCondivisi() }
    }

    func leggiCondivisi() {
        guard accesso else { condivisi = []; return }
        let oggi = Calendar.current.startOfDay(for: .now)
        let da = Calendar.current.date(byAdding: .day, value: -70, to: oggi)!
        let a = Calendar.current.date(byAdding: .day, value: 70, to: oggi)!
        let persone: [Persona] = calendariDiAltri.filter { seguiti.contains($0.calendarIdentifier) }.map { cal in
            var turni: [Turno] = []
            var memo: [MemoCondiviso] = []
            for e in store.events(matching: store.predicateForEvents(withStart: da, end: a, calendars: [cal])) {
                let (t, m) = Condivisione.leggi(note: e.notes ?? "", titolo: e.title ?? "", inizio: e.startDate,
                                                fine: e.endDate, id: e.eventIdentifier ?? UUID().uuidString)
                if let t { turni.append(t) }
                if let m { memo.append(m) }
            }
            return Persona(id: cal.calendarIdentifier, nome: Condivisione.nome(cal.title),
                           turni: turni.sorted { $0.inizio < $1.inizio }, memo: memo.sorted { $0.giorno < $1.giorno })
        }
        if persone != condivisi { condivisi = persone }
    }

    /// Crea (se serve) il tuo calendario iCloud "Turni <nome>".
    func creaCalendario(nome: String) throws -> EKCalendar {
        if let c = calendarioMio {
            let titolo = Condivisione.prefisso + nome
            if c.title != titolo { c.title = titolo; try store.saveCalendar(c, commit: true) }
            return c
        }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = Condivisione.prefisso + nome
        c.cgColor = CGColor(red: 1, green: 0.71, blue: 0.28, alpha: 1)
        // Meglio iCloud, così si può condividere; altrimenti il calendario predefinito.
        c.source = store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        try store.saveCalendar(c, commit: true)
        UserDefaults.standard.set(c.calendarIdentifier, forKey: "calendarioCondiviso")
        return c
    }

    /// Scrive turni e/o memo nel tuo calendario condiviso, cambiando solo gli eventi diversi.
    func condividi(turni: [Turno], memo: [(id: String, testo: String, giorno: Date, fatto: Bool)]) {
        let d = UserDefaults.standard
        guard accesso, d.bool(forKey: "condividiTurni") || d.bool(forKey: "condividiMemo"),
              let cal = calendarioMio else { return }
        let oggi = Calendar.current.startOfDay(for: .now)
        let da = Calendar.current.date(byAdding: .day, value: -35, to: oggi)!
        let a = Calendar.current.date(byAdding: .day, value: 70, to: oggi)!

        struct Voluto: Hashable { var titolo: String; var inizio: Date; var fine: Date; var tuttoIlGiorno: Bool; var note: String }
        var voluti = Set<Voluto>()
        if d.bool(forKey: "condividiTurni") {
            for t in turni where t.inizio >= da && t.inizio < a {
                voluti.insert(Voluto(titolo: Condivisione.titoloTurno(t), inizio: t.inizio, fine: t.fine, tuttoIlGiorno: false,
                                     note: Condivisione.noteTurno(t)))
            }
        }
        if d.bool(forKey: "condividiMemo") {
            for m in memo where m.giorno >= da && m.giorno < a {
                let g = Calendar.current.startOfDay(for: m.giorno)
                voluti.insert(Voluto(titolo: m.testo, inizio: g, fine: g.addingTimeInterval(86399), tuttoIlGiorno: true,
                                     note: Condivisione.noteMemo(id: m.id, fatto: m.fatto)))
            }
        }

        var cambiato = false
        for e in store.events(matching: store.predicateForEvents(withStart: da, end: a, calendars: [cal])) {
            let v = Voluto(titolo: e.title ?? "", inizio: e.startDate,
                           fine: e.isAllDay ? Calendar.current.startOfDay(for: e.startDate).addingTimeInterval(86399) : e.endDate,
                           tuttoIlGiorno: e.isAllDay, note: e.notes ?? "")
            if voluti.contains(v) {
                voluti.remove(v)
            } else {
                try? store.remove(e, span: .thisEvent, commit: false)
                cambiato = true
            }
        }
        for v in voluti {
            let e = EKEvent(eventStore: store)
            e.calendar = cal
            e.title = v.titolo
            e.startDate = v.inizio
            e.endDate = v.fine
            e.isAllDay = v.tuttoIlGiorno
            e.notes = v.note
            try? store.save(e, span: .thisEvent, commit: false)
            cambiato = true
        }
        if cambiato { try? store.commit() }
        UserDefaults.standard.set(Date.now, forKey: "ultimoInvio")
    }
}
