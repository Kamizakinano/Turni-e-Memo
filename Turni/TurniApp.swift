import SwiftUI
import SwiftData

@main
struct TurniApp: App {
    @StateObject private var stato = Stato()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stato)
        }
        .modelContainer(for: [TurnoManuale.self, Memo.self])
    }
}

// Un giorno segnato a mano nel calendario (turno o riposo).
// Le proprietà hanno sempre un valore di default, così le versioni nuove aggiornano i dati senza problemi.
@Model
final class TurnoManuale {
    var giorno: Date = Date.now
    var riposo: Bool = false
    var inizio: Date = Date.now
    var fine: Date = Date.now

    init(giorno: Date, riposo: Bool, inizio: Date, fine: Date) {
        self.giorno = Calendar.current.startOfDay(for: giorno)
        self.riposo = riposo
        self.inizio = inizio
        self.fine = fine
    }

    var turno: Turno {
        Turno(id: "m-\(Int(giorno.timeIntervalSince1970))", inizio: inizio, fine: fine, manuale: true)
    }
}

@Model
final class Memo {
    var uid: UUID = UUID()
    var testo: String = ""
    var giorno: Date = Date.now
    var avviso: Date? = nil
    var fatto: Bool = false

    init(testo: String, giorno: Date, avviso: Date?) {
        self.testo = testo
        self.giorno = Calendar.current.startOfDay(for: giorno)
        self.avviso = avviso
    }
}

/// Unisce giorno e ora (in minuti dalla mezzanotte) in una data.
func data(_ giorno: Date, minuti: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minuti, to: Calendar.current.startOfDay(for: giorno)) ?? giorno
}
