import Foundation
import SwiftUI

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

    var tipo: TipoTurno { .da(inizio: inizio) }
    var ore: Double { max(0, fine.timeIntervalSince(inizio)) / 3600 }

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

    /// Unisce i turni del calendario con quelli segnati a mano:
    /// nei giorni segnati a mano vale la scelta manuale (anche "riposo", che toglie il turno).
    static func unisci(dalCalendario cal: [Turno], manuali: [Turno], riposi: [Date],
                       cal c: Calendar = .current) -> [Turno] {
        let giorniManuali = manuali.map { c.startOfDay(for: $0.inizio) } + riposi.map { c.startOfDay(for: $0) }
        let set = Set(giorniManuali)
        let daCal = cal.filter { !set.contains(c.startOfDay(for: $0.inizio)) }
        return (daCal + manuali).sorted { $0.inizio < $1.inizio }
    }

    /// Settimana (lunedì) che contiene il giorno.
    static func inizioSettimana(_ d: Date) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c.dateInterval(of: .weekOfYear, for: d)?.start ?? c.startOfDay(for: d)
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
