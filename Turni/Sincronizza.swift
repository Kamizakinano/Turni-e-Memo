import Foundation
import EventKit
import WidgetKit
import ActivityKit
import UserNotifications

// Legge i turni di Dayforce dal Calendario dell'iPhone e aggiorna widget, conto alla rovescia e avvisi.
@MainActor
final class Stato: ObservableObject {
    // Si parte dall'ultima lettura di Dayforce (non dai turni uniti alle modifiche a mano,
    // altrimenti i giorni modificati sembravano "cambiati" a ogni apertura e arrivavano tanti avvisi).
    @Published var daCalendario: [Turno] = Archivio.carica("dayforce")
    @Published var accesso = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @Published var scelti: [String] = UserDefaults.standard.stringArray(forKey: "calendari") ?? [] {
        didSet { UserDefaults.standard.set(scelti, forKey: "calendari"); ignoraCambi = true; leggi() }
    }

    let store = EKEventStore()
    /// Quando cambi i calendari scelti, i turni "cambiati" non sono cambi veri di Dayforce.
    private var ignoraCambi = false
    /// Turni e memo delle altre persone (calendari "Turni <nome>" condivisi con te).
    @Published var condivisi: [Persona] = []

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.leggi(); self?.leggiCondivisi() }
        }
    }

    var calendari: [EKCalendar] {
        accesso ? store.calendars(for: .event).sorted { $0.title < $1.title } : []
    }

    func chiediAccesso() async {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        accesso = ok
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if ok && scelti.isEmpty {
            // Prova a trovare da solo il calendario di Dayforce.
            let trovati = store.calendars(for: .event)
                .filter { $0.title.localizedCaseInsensitiveContains("dayforce") }
                .map(\.calendarIdentifier)
            if !trovati.isEmpty { scelti = trovati; return }
        }
        leggi()
    }

    func leggi() {
        defer { leggiCondivisi() }
        accesso = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard accesso else { return }
        let cals = store.calendars(for: .event).filter { scelti.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { daCalendario = []; return }
        let oggi = Calendar.current.startOfDay(for: .now)
        // Anche i turni passati (fino a 2 anni), letti un anno alla volta: EventKit cerca al massimo 4 anni per volta.
        // Il calendario di Dayforce viene prima: se un giorno ha turni in più calendari, vale il suo.
        let ordinati = cals.sorted { a, b in
            let da = a.title.localizedCaseInsensitiveContains("dayforce"), db = b.title.localizedCaseInsensitiveContains("dayforce")
            return da != db ? da : a.title < b.title
        }
        var nuovi: [Turno] = []
        for cal in ordinati {
            var eventi: [EKEvent] = []
            for anno in [-730, -365, 0] {
                let da = Calendar.current.date(byAdding: .day, value: anno, to: oggi)!
                let a = Calendar.current.date(byAdding: .day, value: anno == 0 ? 120 : 365, to: da)!
                eventi += store.events(matching: store.predicateForEvents(withStart: da, end: a, calendars: [cal]))
            }
            nuovi += eventi.filter { !$0.isAllDay && !Condivisione.èDellApp($0) }
                .sorted { $0.startDate < $1.startDate }
                .map { Turno(id: $0.eventIdentifier ?? UUID().uuidString, inizio: $0.startDate, fine: $0.endDate) }
        }
        let senza = Calcoli.soloTurni(nuovi)
        if senza != daCalendario {
            if !ignoraCambi && !daCalendario.isEmpty { registraCambi(prima: daCalendario, dopo: senza) }
            daCalendario = senza
            Archivio.salvaDayforce(senza)
        }
        ignoraCambi = false
    }

    /// Turni cambiati in Dayforce (da oggi in poi): finiscono nello storico e arriva un avviso.
    func registraCambi(prima: [Turno], dopo: [Turno]) {
        let cambi = Calcoli.cambi(prima: prima, dopo: dopo, da: Calendar.current.startOfDay(for: .now))
        guard !cambi.isEmpty, cambi.count <= 20 else { return }   // tanti cambi insieme = calendario nuovo, non un cambio di turno
        for c in cambi {
            let giorno = formatoGiorno(c.giorno, "EEE d MMM").capitalized
            let cosa = c.prima == nil ? "turno aggiunto" : c.dopo == nil ? "turno tolto" : "turno cambiato"
            let dettaglio = "\(Storico.descrivi(c.prima)) → \(Storico.descrivi(c.dopo))"
            Storico.aggiungi("Dayforce", "\(giorno): \(cosa)", dettaglio)
            let n = UNMutableNotificationContent()
            n.title = "🔁 Dayforce ha cambiato un turno"
            n.body = "\(giorno): \(dettaglio)"
            n.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cambio-\(UUID().uuidString)", content: n, trigger: nil))
        }
    }

    /// Salva i turni per il widget e aggiorna conto alla rovescia e avvisi.
    func pubblica(_ turni: [Turno], memoOggi: String?, memo: [(UUID, String, Date)]) {
        Archivio.salva(turni)
        WidgetCenter.shared.reloadAllTimelines()
        ContoAllaRovescia.aggiorna(turni, memo: memoOggi)
        Avvisi.programma(turni, memo: memo)
    }
}

enum ContoAllaRovescia {
    /// Il turno da mostrare: quello in corso, oppure il prossimo se inizia entro 3 ore.
    static func daMostrare(_ turni: [Turno], ora: Date) -> Turno? {
        if let t = Calcoli.inCorso(turni, ora: ora) { return t }
        if let p = Calcoli.prossimo(turni, dopo: ora), p.inizio.timeIntervalSince(ora) <= 3 * 3600 { return p }
        return nil
    }

    /// L'ultimo aggiornamento: quelli nuovi aspettano che finisca, così non nascono due riquadri uguali.
    @MainActor private static var ultimo: Task<Void, Never>?

    @MainActor static func aggiorna(_ turni: [Turno], memo: String?, ora: Date = .now) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let t = daMostrare(turni, ora: ora)
        let prima = ultimo
        ultimo = Task { @MainActor in
            await prima?.value
            var tenuta = false
            for a in Activity<TurnoAttributes>.activities {
                let s = a.content.state
                // Ne resta al massimo una, quella del turno giusto; le altre (anche i doppioni) si chiudono.
                if let t, !tenuta, s.inizio == t.inizio, s.fine == t.fine {
                    tenuta = true
                    await a.update(ActivityContent(state: .init(inizio: t.inizio, fine: t.fine, memo: memo), staleDate: t.fine))
                } else {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
            guard let t, !tenuta else { return }
            let contenuto = ActivityContent(state: TurnoAttributes.ContentState(inizio: t.inizio, fine: t.fine, memo: memo), staleDate: t.fine)
            _ = try? Activity.request(attributes: TurnoAttributes(tipo: t.tipo.rawValue), content: contenuto, pushType: nil)
        }
    }
}

enum Avvisi {
    static func programma(_ turni: [Turno], memo: [(UUID, String, Date)], ora: Date = .now) {
        let centro = UNUserNotificationCenter.current()
        centro.getPendingNotificationRequests { vecchi in
            // Gli avvisi di fine pausa restano: li ha chiesti l'utente.
            centro.removePendingNotificationRequests(withIdentifiers: vecchi.map(\.identifier).filter { !$0.hasPrefix("fine-pausa-") })
            let limite = ora.addingTimeInterval(14 * 86400)
            for t in turni where t.inizio > ora && t.inizio < limite {
                let c = UNMutableNotificationContent()
                c.title = "\(t.tipo.emoji) Inizia il turno di \(t.tipo.nome.lowercased())"
                c.body = "\(t.orario). Apri l'app per il conto alla rovescia sulla schermata di blocco."
                c.sound = .default
                aggiungi(centro, "turno-\(t.id)", c, t.inizio)
            }
            for t in turni where !Pause.fatta(t.id) {
                let quando = t.inizio.addingTimeInterval(Pause.dopoOre * 3600)
                guard quando > ora, quando < t.fine, quando < limite else { continue }
                let c = UNMutableNotificationContent()
                c.title = "☕ Sono \(Int(Pause.dopoOre)) ore che lavori"
                c.body = "Non hai ancora fatto la pausa (minimo \(Turno.pausaMinima) min)."
                c.sound = .default
                c.categoryIdentifier = "PAUSA"
                c.userInfo = ["turno": t.id]
                aggiungi(centro, "pausa-\(t.id)", c, quando)
            }
            // La sera prima di ogni turno: ricordati la sveglia.
            let oraSveglia = UserDefaults.standard.object(forKey: "oraAvvisoSveglia") as? Int ?? 21 * 60
            if UserDefaults.standard.object(forKey: "avvisoSveglia") as? Bool ?? true {
                for t in turni where t.inizio < limite && !t.assenza {
                    guard let ieri = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: t.inizio)),
                          let quando = Calendar.current.date(byAdding: .minute, value: oraSveglia, to: ieri),
                          quando > ora, quando < t.inizio else { continue }
                    let c = UNMutableNotificationContent()
                    c.title = "⏰ Domani attacchi alle \(Turno.ora(t.inizio))"
                    c.body = "Ricordati di mettere la sveglia."
                    c.sound = .default
                    c.categoryIdentifier = "SVEGLIA"
                    aggiungi(centro, "sveglia-\(t.id)", c, quando)
                }
            }
            for (id, testo, quando) in memo where quando > ora {
                let c = UNMutableNotificationContent()
                c.title = "📝 Memo"
                c.body = testo
                c.sound = .default
                aggiungi(centro, "memo-\(id.uuidString)", c, quando)
            }
        }
    }

    private static func aggiungi(_ centro: UNUserNotificationCenter, _ id: String, _ c: UNMutableNotificationContent, _ quando: Date) {
        let comp = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: quando)
        centro.add(UNNotificationRequest(identifier: id, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)))
    }
}
