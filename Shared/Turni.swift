import Foundation
import SwiftUI
import UserNotifications

// Tipo di turno: si capisce dall'ora di inizio (prima delle 12 = mattina).
enum TipoTurno: String, Codable, CaseIterable {
    case mattina, pomeriggio

    static func da(inizio: Date, calendario: Calendar = .current) -> TipoTurno {
        calendario.component(.hour, from: inizio) < 12 ? .mattina : .pomeriggio
    }

    var nome: String { self == .mattina ? "Mattina" : "Pomeriggio" }
    var emoji: String { self == .mattina ? "☀️" : "🌙" }
    var colore: Color { self == .mattina ? AppColor.mattina : AppColor.pomeriggio }
}

// Un turno con orari esatti (preso da Dayforce tramite il calendario, oppure segnato a mano).
struct Turno: Codable, Hashable, Identifiable {
    var id: String
    var inizio: Date
    var fine: Date
    var manuale: Bool = false
    /// Pausa non pagata in minuti (se manca vale quella minima).
    var pausaMin: Int? = nil

    /// La pausa non pagata è di almeno 11 minuti per turno, anche se Dayforce ne segna 10.
    static let pausaMinima = 11
    var pausa: Int { max(Turno.pausaMinima, pausaMin ?? 0) }

    var tipo: TipoTurno { .da(inizio: inizio) }
    /// Ore pagate: durata del turno meno la pausa.
    var ore: Double { max(0, fine.timeIntervalSince(inizio) - Double(pausa * 60)) / 3600 }

    var orario: String { "\(Turno.ora(inizio)) – \(Turno.ora(fine))" }

    static func ora(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

enum AppColor {
    static let ardesia = Color(red: 0x5D / 255, green: 0x75 / 255, blue: 0x84 / 255)
    static let mattina = Color(red: 1, green: 0xB5 / 255, blue: 0x47 / 255)
    static let pomeriggio = ardesia
    static let fng = Color(red: 0x2E / 255, green: 0x9D / 255, blue: 0x5B / 255)
    static let riposo = Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xDC / 255)
    static let sfondo = Color(red: 0xF4 / 255, green: 0xF6 / 255, blue: 0xF8 / 255)
}

// Calcoli sui turni, usati dall'app, dal widget e dalle prove.
enum Calcoli {
    /// Il turno in corso adesso, se c'è.
    static func inCorso(_ turni: [Turno], ora: Date) -> Turno? {
        turni.first { $0.inizio <= ora && ora < $0.fine }
    }

    /// Il primo turno che inizia dopo `ora`.
    static func prossimo(_ turni: [Turno], dopo ora: Date) -> Turno? {
        turni.filter { $0.inizio > ora }.min { $0.inizio < $1.inizio }
    }

    /// Il turno che inizia in quel giorno.
    static func turno(_ turni: [Turno], giorno: Date, calendario: Calendar = .current) -> Turno? {
        turni.filter { calendario.isDate($0.inizio, inSameDayAs: giorno) }.min { $0.inizio < $1.inizio }
    }

    /// Il turno di domani rispetto a `ora`.
    static func domani(_ turni: [Turno], ora: Date, calendario: Calendar = .current) -> Turno? {
        guard let d = calendario.date(byAdding: .day, value: 1, to: ora) else { return nil }
        return turno(turni, giorno: d, calendario: calendario)
    }

    /// Ore dei turni che iniziano tra `da` (compreso) e `a` (escluso).
    static func ore(_ turni: [Turno], da: Date, a: Date) -> Double {
        turni.filter { $0.inizio >= da && $0.inizio < a }.reduce(0) { $0 + $1.ore }
    }

    /// Toglie i doppioni: lo stesso turno in due calendari (es. Dayforce e SuperShift) conta una volta.
    static func senzaDoppioni(_ turni: [Turno]) -> [Turno] {
        var visti = Set<String>()
        return turni.sorted { $0.inizio < $1.inizio }.filter { t in
            let k = "\(Int(t.inizio.timeIntervalSince1970 / 60))-\(Int(t.fine.timeIntervalSince1970 / 60))"
            return visti.insert(k).inserted
        }
    }

    /// Unisce i turni del calendario con quelli segnati a mano:
    /// nei giorni segnati a mano vale la scelta manuale (anche "riposo", che toglie il turno).
    static func unisci(dalCalendario cal: [Turno], manuali: [Turno], riposi: [Date],
                       cal c: Calendar = .current) -> [Turno] {
        let giorniManuali = manuali.map { c.startOfDay(for: $0.inizio) } + riposi.map { c.startOfDay(for: $0) }
        let set = Set(giorniManuali)
        let daCal = cal.filter { !set.contains(c.startOfDay(for: $0.inizio)) }
        return (daCal + manuali).sorted { $0.inizio < $1.inizio }
    }

    static let oreContratto = 40.0
    static let oreFNG = 44.0

    /// Bonus FNG: nella settimana (lunedì–domenica) hai lavorato la domenica e fatto almeno 44 ore pagate.
    static func fng(_ turni: [Turno], lunedi: Date) -> Bool {
        let c = Calendar.current
        guard let domenica = c.date(byAdding: .day, value: 6, to: lunedi),
              let fine = c.date(byAdding: .day, value: 7, to: lunedi) else { return false }
        return turno(turni, giorno: domenica) != nil && ore(turni, da: lunedi, a: fine) >= oreFNG - 0.001
    }

    /// I lunedì delle settimane intere (lunedì–domenica) che toccano il mese.
    static func settimane(mese: Date) -> [Date] {
        let c = Calendar.current
        let inizio = c.date(from: c.dateComponents([.year, .month], from: mese))!
        let fine = c.date(byAdding: .month, value: 1, to: inizio)!
        var lunedi = inizioSettimana(inizio)
        var tutte: [Date] = []
        while lunedi < fine {
            tutte.append(lunedi)
            lunedi = c.date(byAdding: .day, value: 7, to: lunedi)!
        }
        return tutte
    }

    /// Numero della settimana dell'anno (KW), come in Dayforce: la settimana parte il lunedì.
    static func kw(_ d: Date) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: d)
    }

    /// Settimana (lunedì) che contiene il giorno.
    static func inizioSettimana(_ d: Date) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c.dateInterval(of: .weekOfYear, for: d)?.start ?? c.startOfDay(for: d)
    }
}

// Turni confermati a fine giornata ("Sì, giusto" o modificati), per giorno.
enum Conferme {
    static func chiave(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    static func confermato(_ d: Date) -> Bool {
        (Archivio.defaults.stringArray(forKey: "confermati") ?? []).contains(chiave(d))
    }

    static func conferma(_ d: Date) {
        var tutti = Archivio.defaults.stringArray(forKey: "confermati") ?? []
        if !tutti.contains(chiave(d)) { tutti.append(chiave(d)) }
        Archivio.defaults.set(Array(tutti.suffix(400)), forKey: "confermati")
    }

    /// L'ultimo turno finito negli ultimi 3 giorni e non ancora confermato.
    static func daConfermare(_ turni: [Turno], ora: Date, confermato: (Date) -> Bool = confermato) -> Turno? {
        turni.filter { $0.fine <= ora && $0.fine > ora.addingTimeInterval(-3 * 86400) && !confermato($0.inizio) }
            .max { $0.inizio < $1.inizio }
    }
}

// Pause già fatte, per non mandare l'avviso dopo 5 ore.
enum Pause {
    static let dopoOre = 5.0

    static func fatta(_ id: String) -> Bool {
        (Archivio.defaults.stringArray(forKey: "pauseFatte") ?? []).contains(id)
    }

    static func segna(_ id: String, fatta: Bool) {
        var tutte = Archivio.defaults.stringArray(forKey: "pauseFatte") ?? []
        tutte.removeAll { $0 == id }
        if fatta {
            tutte.append(id)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pausa-\(id)"])
        }
        Archivio.defaults.set(Array(tutte.suffix(200)), forKey: "pauseFatte")
    }
}

// Turni e memo condivisi tra l'app e il widget della schermata di blocco.
enum Archivio {
    static let gruppo = "group.com.tuonome.turni"
    static var defaults: UserDefaults { UserDefaults(suiteName: gruppo) ?? .standard }

    static func salva(_ turni: [Turno]) {
        if let d = try? JSONEncoder().encode(turni) { defaults.set(d, forKey: "turni") }
    }

    static func carica() -> [Turno] {
        guard let d = defaults.data(forKey: "turni") else { return [] }
        return (try? JSONDecoder().decode([Turno].self, from: d)) ?? []
    }
}
