import SwiftUI
import SwiftData
import UserNotifications

@main
struct TurniApp: App {
    @StateObject private var stato = Stato()
    @UIApplicationDelegateAdaptor(Delegato.self) var delegato

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stato)
        }
        .modelContainer(for: [TurnoManuale.self, Memo.self])
    }
}

// Riceve i tocchi sui pulsanti degli avvisi ("Fatta", "Inizio ora").
final class Delegato: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let centro = UNUserNotificationCenter.current()
        centro.delegate = self
        let fatta = UNNotificationAction(identifier: "FATTA", title: "✅ Fatta")
        let inizio = UNNotificationAction(identifier: "INIZIO", title: "⏱ Inizio ora")
        let sveglie = UNNotificationAction(identifier: "SVEGLIE", title: "⏰ Apri Sveglie", options: [.foreground])
        centro.setNotificationCategories([
            UNNotificationCategory(identifier: "PAUSA", actions: [fatta, inizio], intentIdentifiers: []),
            UNNotificationCategory(identifier: "SVEGLIA", actions: [sveglie], intentIdentifiers: [])
        ])
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == "SVEGLIE" || response.notification.request.content.categoryIdentifier == "SVEGLIA" {
            // Apre l'app Orologio sulle sveglie.
            if let url = URL(string: "clock-alarm://") { await UIApplication.shared.open(url) }
            return
        }
        let id = response.notification.request.content.userInfo["turno"] as? String ?? ""
        guard !id.isEmpty else { return }
        switch response.actionIdentifier {
        case "FATTA":
            Pause.segna(id, fatta: true)
        case "INIZIO":
            Pause.segna(id, fatta: true)
            let c = UNMutableNotificationContent()
            c.title = "☕ Pausa finita"
            c.body = "Sono passati \(Turno.pausaMinima) minuti."
            c.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "fine-pausa-\(id)", content: c,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(Turno.pausaMinima * 60), repeats: false)))
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
    var pausa: Int = 11
    /// Dall'importazione di SuperShift: codice (MA, PO, RI, MI, FE, PE) e ore pagate (-1 = da calcolare).
    var codice: String = ""
    var orePagate: Double = -1

    init(giorno: Date, riposo: Bool, inizio: Date, fine: Date) {
        self.giorno = Calendar.current.startOfDay(for: giorno)
        self.riposo = riposo
        self.inizio = inizio
        self.fine = fine
    }

    var turno: Turno {
        Turno(id: "m-\(Int(giorno.timeIntervalSince1970))", inizio: inizio, fine: fine, manuale: true, pausaMin: pausa,
              orePagate: orePagate >= 0 ? orePagate : nil, codice: codice.isEmpty ? nil : codice)
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
