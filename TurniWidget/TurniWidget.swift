import WidgetKit
import SwiftUI
import ActivityKit

@main
struct TurniWidgetBundle: WidgetBundle {
    var body: some Widget {
        TurnoWidget()
        SettimanaWidget()
        ProssimiWidget()
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
                    Mancano(fine: t.fine).font(.title3.bold()).monospacedDigit()
                    Avanzamento(inizio: t.inizio, fine: t.fine)
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
                    Mancano(fine: t.fine).font(.title.bold()).monospacedDigit()
                    Avanzamento(inizio: t.inizio, fine: t.fine)
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
                    Mancano(fine: ctx.state.fine).font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(AppColor.mattina).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Avanzamento(inizio: ctx.state.inizio, fine: ctx.state.fine)
                        .tint(AppColor.mattina)
                    HStack { Text(Turno.ora(ctx.state.inizio)); Spacer(); Text(Turno.ora(ctx.state.fine)) }.font(.caption)
                }
            } compactLeading: {
                Text(tipo.emoji)
            } compactTrailing: {
                Mancano(fine: ctx.state.fine).monospacedDigit().frame(maxWidth: 52)
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
                        Mancano(fine: stato.fine).font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                }
                Avanzamento(inizio: stato.inizio, fine: stato.fine)
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

// MARK: - Poca batteria: il tempo cambia una volta al minuto e la barra non si anima

struct Mancano: View {
    var fine: Date
    var body: some View {
        if #available(iOS 18.0, *) {
            Text(.currentDate, format: .timer(countingDownIn: Date.now..<max(fine, Date.now.addingTimeInterval(1)),
                                              showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(60)))
        } else {
            Text(fine, style: .timer)
        }
    }
}

struct Avanzamento: View {
    var inizio: Date
    var fine: Date
    var body: some View {
        let tot = max(1, fine.timeIntervalSince(inizio))
        ProgressView(value: min(tot, max(0, Date.now.timeIntervalSince(inizio))), total: tot)
    }
}

// MARK: - Widget nella Home

struct VoceHome: TimelineEntry {
    let date: Date
    let turni: [Turno]
}

struct FornitoreHome: TimelineProvider {
    func placeholder(in context: Context) -> VoceHome { VoceHome(date: .now, turni: []) }
    func getSnapshot(in context: Context, completion: @escaping (VoceHome) -> Void) {
        completion(VoceHome(date: .now, turni: Archivio.carica()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoceHome>) -> Void) {
        let turni = Archivio.carica()
        let ora = Date.now
        // Si aggiorna a mezzanotte e alla fine di ogni turno di oggi, non di continuo.
        var punti: Set<Date> = [ora]
        if let m = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: ora)) { punti.insert(m) }
        for t in turni where t.fine > ora && t.fine < ora.addingTimeInterval(86400) { punti.insert(t.fine) }
        completion(Timeline(entries: punti.sorted().map { VoceHome(date: $0, turni: turni) }, policy: .atEnd))
    }
}

struct SettimanaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SettimanaWidget", provider: FornitoreHome()) { v in
            let lunedi = Calcoli.inizioSettimana(v.date)
            let fine = Calendar.current.date(byAdding: .day, value: 7, to: lunedi)!
            let ore = Calcoli.ore(v.turni, da: lunedi, a: fine)
            let domenica = Calcoli.turno(v.turni, giorno: Calendar.current.date(byAdding: .day, value: 6, to: lunedi)!) != nil
            VStack(alignment: .leading, spacing: 3) {
                Text("SETTIMANA \(Calcoli.kw(lunedi))").font(.caption2.bold()).foregroundStyle(.secondary)
                Text(oreBreve(ore)).font(.title2.weight(.heavy)).minimumScaleFactor(0.7)
                Text(String(format: "%.2f h su 40", ore).replacingOccurrences(of: ".", with: ",")).font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: min(ore, 44), total: 44).tint(AppColor.mattina)
                if Calcoli.fng(v.turni, lunedi: lunedi) {
                    Text("✅ FNG").font(.caption.bold()).foregroundStyle(AppColor.fng)
                } else if domenica {
                    Text("FNG: lavori domenica").font(.caption2.bold()).foregroundStyle(AppColor.fng)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Ore della settimana")
        .description("Ore pagate della settimana e FNG.")
        .supportedFamilies([.systemSmall])
    }
}

struct ProssimiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProssimiWidget", provider: FornitoreHome()) { v in
            let oggi = Calendar.current.startOfDay(for: v.date)
            let saldo = BancaOre.daInizioAnno(v.turni, ora: v.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PROSSIMI GIORNI").font(.caption2.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text("banca ore " + (saldo >= 0 ? "+" : "−") + oreBreve(abs(saldo))).font(.caption2.bold())
                        .foregroundStyle(saldo >= 0 ? AppColor.fng : .red)
                }
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        let g = Calendar.current.date(byAdding: .day, value: i, to: oggi)!
                        let t = Calcoli.turno(v.turni, giorno: g)
                        VStack(spacing: 1) {
                            Text(i == 0 ? "OGGI" : giornoBreve(g)).font(.system(size: 10, weight: .heavy))
                            Text(t.map { Turno.ora($0.inizio) } ?? "—").font(.system(size: 11, weight: .semibold))
                            Text(t.map { Turno.ora($0.fine) } ?? " ").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(t == nil ? Color.primary : .white)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(t?.tipo.colore ?? AppColor.riposo, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Prossimi turni")
        .description("I turni dei prossimi 5 giorni e la banca ore.")
        .supportedFamilies([.systemMedium])
    }
}

func oreBreve(_ ore: Double) -> String {
    let m = Int((ore * 60).rounded())
    return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)"
}

func giornoBreve(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "EEE d"
    return f.string(from: d).uppercased()
}
