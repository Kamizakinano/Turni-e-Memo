import WidgetKit
import SwiftUI
import ActivityKit

@main
struct TurniWidgetBundle: WidgetBundle {
    var body: some Widget {
        TurnoWidget()
        TurnoLiveActivity()
    }
}

// MARK: - Widget per la schermata di blocco: turno di domani e quanto manca alla fine

struct Voce: TimelineEntry {
    let date: Date
    let inCorso: Turno?
    let domani: Turno?
}

struct Fornitore: TimelineProvider {
    func voce(_ turni: [Turno], _ d: Date) -> Voce {
        Voce(date: d, inCorso: Calcoli.inCorso(turni, ora: d), domani: Calcoli.domani(turni, ora: d))
    }

    func placeholder(in context: Context) -> Voce {
        let i = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now.addingTimeInterval(86400))!
        return Voce(date: .now, inCorso: nil, domani: Turno(id: "x", inizio: i, fine: i.addingTimeInterval(8 * 3600)))
    }

    func getSnapshot(in context: Context, completion: @escaping (Voce) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : voce(Archivio.carica(), .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Voce>) -> Void) {
        let turni = Archivio.carica()
        let ora = Date.now
        let limite = ora.addingTimeInterval(3 * 86400)
        // Il widget cambia a inizio e fine di ogni turno e a mezzanotte.
        var punti: Set<Date> = [ora]
        for t in turni {
            if t.inizio > ora && t.inizio < limite { punti.insert(t.inizio) }
            if t.fine > ora && t.fine < limite { punti.insert(t.fine) }
        }
        for g in 1...3 {
            if let m = Calendar.current.date(byAdding: .day, value: g, to: Calendar.current.startOfDay(for: ora)) { punti.insert(m) }
        }
        completion(Timeline(entries: punti.sorted().map { voce(turni, $0) }, policy: .atEnd))
    }
}

struct VistaWidget: View {
    @Environment(\.widgetFamily) var famiglia
    var voce: Voce

    var body: some View {
        switch famiglia {
        case .accessoryInline:
            if let t = voce.inCorso {
                Text("\(t.tipo.emoji) Fine turno alle \(Turno.ora(t.fine))")
            } else {
                Text(voce.domani.map { "Domani \($0.tipo.emoji) \(Turno.ora($0.inizio))–\(Turno.ora($0.fine))" } ?? "Domani riposo")
            }
        case .accessoryRectangular:
            if let t = voce.inCorso {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(t.tipo.emoji) Mancano").font(.caption.bold())
                    Text(t.fine, style: .timer).font(.title3.bold()).monospacedDigit()
                    ProgressView(timerInterval: t.inizio...t.fine, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("DOMANI").font(.caption2.bold())
                    Text(voce.domani.map { "\($0.tipo.emoji) \($0.tipo.nome)" } ?? "😴 Riposo").font(.headline)
                    if let d = voce.domani { Text(d.orario).font(.caption) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if let t = voce.inCorso {
                    Text("\(t.tipo.emoji) MANCANO").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(t.fine, style: .timer).font(.title.bold()).monospacedDigit()
                    ProgressView(timerInterval: t.inizio...t.fine, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(t.tipo.colore)
                    Text(t.orario).font(.caption)
                } else {
                    Text("DOMANI").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(voce.domani.map { "\($0.tipo.emoji) \($0.tipo.nome)" } ?? "😴 Riposo").font(.headline)
                    if let d = voce.domani { Text(d.orario).font(.subheadline) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TurnoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TurnoWidget", provider: Fornitore()) { voce in
            VistaWidget(voce: voce).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Turni")
        .description("Il turno di domani e quanto manca alla fine del turno.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .systemSmall])
    }
}

// MARK: - Conto alla rovescia sulla schermata di blocco e nella Dynamic Island

struct TurnoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TurnoAttributes.self) { ctx in
            Schermata(tipo: TipoTurno(rawValue: ctx.attributes.tipo) ?? .mattina, stato: ctx.state, finito: ctx.isStale)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { ctx in
            let tipo = TipoTurno(rawValue: ctx.attributes.tipo) ?? .mattina
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(tipo.emoji) Turno di \(tipo.nome.lowercased())").font(.subheadline.bold())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ctx.state.fine, style: .timer).font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(AppColor.mattina).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: ctx.state.inizio...ctx.state.fine, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(AppColor.mattina)
                    HStack { Text(Turno.ora(ctx.state.inizio)); Spacer(); Text(Turno.ora(ctx.state.fine)) }.font(.caption)
                }
            } compactLeading: {
                Text(tipo.emoji)
            } compactTrailing: {
                Text(ctx.state.fine, style: .timer).monospacedDigit().frame(maxWidth: 52)
                    .foregroundStyle(AppColor.mattina)
            } minimal: {
                Text(tipo.emoji)
            }
        }
    }
}

struct Schermata: View {
    var tipo: TipoTurno
    var stato: TurnoAttributes.ContentState
    var finito: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(tipo.colore).frame(width: 8)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TURNO DI \(tipo.nome.uppercased())").font(.caption.bold()).foregroundStyle(.gray)
                        Text(finito ? "Turno finito" : "Mancano alla fine")
                            .font(.title3.bold())
                    }
                    Spacer()
                    if !finito {
                        Text(stato.fine, style: .timer).font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                }
                ProgressView(timerInterval: stato.inizio...stato.fine, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(tipo.colore)
                HStack { Text(Turno.ora(stato.inizio)); Spacer(); Text(Turno.ora(stato.fine)) }
                    .font(.caption).foregroundStyle(.gray)
                if let m = stato.memo {
                    Text("✎ \(m)").font(.subheadline).italic().foregroundStyle(.gray)
                }
            }
            .foregroundStyle(.black)
            .padding(14)
        }
    }
}
