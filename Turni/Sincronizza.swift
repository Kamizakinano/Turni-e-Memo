import Foundation
import EventKit
import WidgetKit
import ActivityKit
import UserNotifications

// Legge i turni di Dayforce dal Calendario dell'iPhone e aggiorna widget, conto alla rovescia e avvisi.
@MainActor
final class Stato: ObservableObject {
    @Published var daCalendario: [Turno] = Archivio.carica().filter { !$0.manuale }
    @Published var accesso = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @Published var scelti: [String] = UserDefaults.standard.stringArray(forKey: "calendari") ?? [] {
        didSet { UserDefaults.standard.set(scelti, forKey: "calendari"); leggi() }
    }

    let store = EKEventStore()
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
        let da = Calendar.current.date(byAdding: .day, value: -70, to: oggi)!
        let a = Calendar.current.date(byAdding: .day, value: 70, to: oggi)!
        let eventi = store.events(matching: store.predicateForEvents(withStart: da, end: a, calendars: cals))
        let nuovi = eventi.filter { !$0.isAllDay && $0.endDate > $0.startDate && !Condivisione.èDellApp($0) }
            .map { Turno(id: $0.eventIdentifier ?? UUID().uuidString, inizio: $0.startDate, fine: $0.endDate) }
            .sorted { $0.inizio < $1.inizio }
        if nuovi != daCalendario { daCalendario = nuovi }
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

    static func aggiorna(_ turni: [Turno], memo: String?, ora: Date = .now) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let t = daMostrare(turni, ora: ora)
        Task {
            for a in Activity<TurnoAttributes>.activities {
                let s = a.content.state
                if t == nil || s.inizio != t!.inizio || s.fine != t!.fine {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
            guard let t else { return }
            let stato = TurnoAttributes.ContentState(inizio: t.inizio, fine: t.fine, memo: memo)
            let contenuto = ActivityContent(state: stato, staleDate: t.fine)
            if let a = Activity<TurnoAttributes>.activities.first(where: { $0.content.state.inizio == t.inizio && $0.content.state.fine == t.fine }) {
                await a.update(contenuto)
            } else {
                _ = try? Activity.request(attributes: TurnoAttributes(tipo: t.tipo.rawValue), content: contenuto, pushType: nil)
            }
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
