import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var stato: Stato
    @Query var manuali: [TurnoManuale]
    @Query(sort: \Memo.giorno) var memo: [Memo]
    @Environment(\.scenePhase) var fase
    /// Di chi sono i turni mostrati: nil = i miei, altrimenti l'id del calendario condiviso.
    @State private var chi: String?

    var persona: Persona? { chi.flatMap { id in stato.condivisi.first { $0.id == id } } }
    var turniVisti: [Turno] { persona?.turni ?? turni }

    var turni: [Turno] {
        Calcoli.unisci(dalCalendario: stato.daCalendario,
                       manuali: manuali.filter { !$0.riposo }.map(\.turno),
                       riposi: manuali.filter(\.riposo).map(\.giorno))
    }

    var body: some View {
        TabView {
            OggiView(turni: turniVisti, nome: persona?.nome, chi: $chi)
                .tabItem { Label("Oggi", systemImage: "sun.max.fill") }
            CalendarioView(turni: turniVisti, nome: persona?.nome, chi: $chi)
                .tabItem { Label("Calendario", systemImage: "calendar") }
            MemoView()
                .tabItem { Label("Memo", systemImage: "note.text") }
            OreView(turni: turni)
                .tabItem { Label("Ore", systemImage: "clock") }
            AltroView(turni: turni)
                .tabItem { Label("Altro", systemImage: "gearshape") }
        }
        .tint(AppColor.ardesia)
        .onAppear { stato.leggi(); pubblica(); sceltaIniziale() }
        .onChange(of: turni) { pubblica() }
        .onChange(of: memo.map { "\($0.testo)|\($0.fatto)|\($0.giorno.timeIntervalSince1970)" }) { pubblica() }
        .onChange(of: stato.condivisi) { sceltaIniziale() }
        .onReceive(NotificationCenter.default.publisher(for: .condivisioneCambiata)) { _ in pubblica() }
        .onChange(of: fase) { if fase == .active { stato.leggi(); pubblica() } }
    }

    func pubblica() {
        let oggi = memo.first { !$0.fatto && Calendar.current.isDateInToday($0.giorno) }?.testo
        let avvisi = memo.compactMap { m in m.fatto ? nil : m.avviso.map { (m.uid, m.testo, $0) } }
        stato.pubblica(turni, memoOggi: oggi, memo: avvisi)
        stato.condividi(turni: turni, memo: memo.map { (id: $0.uid.uuidString, testo: $0.testo, giorno: $0.giorno, fatto: $0.fatto) })
    }

    /// Chi non ha turni suoi (es. chi riceve solo la condivisione) vede subito quelli dell'altra persona.
    func sceltaIniziale() {
        if let c = chi, !stato.condivisi.contains(where: { $0.id == c }) { chi = nil }
        if chi == nil, turni.isEmpty, let p = stato.condivisi.first(where: { !$0.turni.isEmpty }) { chi = p.id }
    }
}

/// "I miei" / persona: compare solo se qualcuno ti condivide i suoi turni.
struct SceltaPersona: View {
    @EnvironmentObject var stato: Stato
    @Binding var chi: String?

    var body: some View {
        let altri = stato.condivisi.filter { !$0.turni.isEmpty }
        if !altri.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("I miei", scelto: chi == nil) { chi = nil }
                    ForEach(altri) { p in chip("👤 \(p.nome)", scelto: chi == p.id) { chi = p.id } }
                }
            }
        }
    }

    func chip(_ t: String, scelto: Bool, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(t).font(.subheadline.bold())
                .foregroundStyle(scelto ? .white : .primary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(scelto ? AppColor.ardesia : .white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let condivisioneCambiata = Notification.Name("condivisioneCambiata")
}

// Riquadro bianco con gli angoli arrotondati, come nelle anteprime.
struct Riquadro<C: View>: View {
    @ViewBuilder var contenuto: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { contenuto }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct Riga: View {
    var titolo: String
    var valore: String
    var body: some View {
        HStack { Text(titolo); Spacer(); Text(valore).bold() }.font(.subheadline)
    }
}

func formatoGiorno(_ d: Date, _ formato: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = formato
    return f.string(from: d)
}

/// "40 h 5 min"
func oreMinuti(_ ore: Double) -> String {
    let m = Int((ore * 60).rounded())
    return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
}

/// "40,08 h" (ore in centesimi)
func centesimi(_ ore: Double) -> String {
    String(format: "%.2f h", ore).replacingOccurrences(of: ".", with: ",")
}

/// Ore in due modi: "40 h 5 min" e sotto, piccolo, "40,08 h".
struct OreTesto: View {
    var ore: Double
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(oreMinuti(ore)).bold()
            Text(centesimi(ore)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

struct RigaOre: View {
    var titolo: String
    var ore: Double
    var body: some View {
        HStack { Text(titolo); Spacer(); OreTesto(ore: ore) }.font(.subheadline)
    }
}

func formatoOre(_ ore: Double) -> String {
    ore == ore.rounded() ? "\(Int(ore))" : String(format: "%.1f", ore).replacingOccurrences(of: ".", with: ",")
}

func durata(_ secondi: TimeInterval) -> String {
    let m = max(0, Int(secondi) / 60)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

// MARK: - Oggi

struct OggiView: View {
    @EnvironmentObject var stato: Stato
    @Query(sort: \Memo.giorno) var memo: [Memo]
    var turni: [Turno]
    var nome: String?
    @Binding var chi: String?

    @State private var modifica: CalendarioView.Giorno?
    @State private var aggiorna = false

    func etichetta(_ t: String) -> String { nome.map { "\($0.uppercased()) · \(t)" } ?? t }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let ora = ctx.date
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Oggi").font(.largeTitle.bold())
                        Text(formatoGiorno(ora, "EEEE d MMMM").capitalized).foregroundStyle(.secondary)
                    }
                    SceltaPersona(chi: $chi)
                    if !stato.accesso {
                        Riquadro {
                            Text("Collega Dayforce").font(.headline)
                            Text("L'app legge i turni con gli orari esatti dal calendario dell'iPhone, dove Dayforce li copia.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Collega il calendario") { Task { await stato.chiediAccesso() } }
                                .buttonStyle(.borderedProminent).tint(AppColor.ardesia)
                        }
                    }
                    cartaOggi(ora)
                    settimana(ora)
                    memoOggi
                }
                .padding(16)
            }
            .background(AppColor.sfondo)
            .id(aggiorna)
        }
        .sheet(item: $modifica) { g in
            SceltaTurno(giorno: g.id, dayforce: Calcoli.turno(stato.daCalendario, giorno: g.id))
                .presentationDetents([.large])
        }
    }

    @ViewBuilder func cartaOggi(_ ora: Date) -> some View {
        let oggi = Calcoli.inCorso(turni, ora: ora) ?? Calcoli.turno(turni, giorno: ora)
        if nome == nil, let d = Conferme.daConfermare(turni, ora: ora) {
            cartaConferma(d)
        }
        if let t = oggi, t.fine > ora {
            // Turno di oggi ancora da fare o in corso.
            VStack(alignment: .leading, spacing: 4) {
                Text(etichetta(t.inizio <= ora ? "TURNO IN CORSO" : "TURNO DI OGGI")).font(.footnote.bold()).opacity(0.9)
                Text("\(t.tipo.emoji) \(t.tipo.nome)").font(.system(size: 30, weight: .heavy))
                Text("\(t.orario) · \(oreMinuti(t.ore))").font(.title3)
                if t.inizio <= ora {
                    Text("Mancano \(durata(t.fine.timeIntervalSince(ora)))").font(.headline)
                    if nome == nil { BottonePausa(turno: t) }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(t.tipo.colore, in: RoundedRectangle(cornerRadius: 20))
            cartaDomani(ora)
        } else {
            if oggi == nil {
                Text(etichetta("OGGI") + "\n😴 Riposo")
                    .font(.system(size: 26, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(AppColor.riposo, in: RoundedRectangle(cornerRadius: 20))
            } else if let t = oggi, nome == nil, Conferme.confermato(t.inizio) {
                Riquadro {
                    HStack {
                        Text("✅ Oggi \(t.orario)")
                        Spacer()
                        Text("confermato").bold().foregroundStyle(AppColor.fng)
                    }
                }
            }
            cartaProssimo(ora)
        }
    }

    /// Il prossimo turno in grande, con il giorno.
    @ViewBuilder func cartaProssimo(_ ora: Date) -> some View {
        let p = Calcoli.prossimo(turni, dopo: ora)
        VStack(alignment: .leading, spacing: 4) {
            if let p {
                let giorni = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: ora),
                                                             to: Calendar.current.startOfDay(for: p.inizio)).day ?? 0
                let quando = giorni == 1 ? "DOMANI " + formatoGiorno(p.inizio, "EEE d").uppercased()
                    : formatoGiorno(p.inizio, "EEEE d MMMM").uppercased()
                Text(etichetta("PROSSIMO TURNO · \(quando)")).font(.footnote.bold()).opacity(0.9)
                Text("\(p.tipo.emoji) \(p.tipo.nome)").font(.system(size: 30, weight: .heavy))
                Text("\(p.orario) · \(oreMinuti(p.ore))").font(.title3)
                if giorni > 1 { Text("tra \(giorni) giorni").font(.subheadline) }
            } else {
                Text(etichetta("PROSSIMO TURNO")).font(.footnote.bold()).opacity(0.9)
                Text("Nessun turno in calendario").font(.title3.weight(.heavy))
            }
        }
        .foregroundStyle(p == nil ? Color.primary : .white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(p?.tipo.colore ?? AppColor.riposo, in: RoundedRectangle(cornerRadius: 20))
    }

    func cartaConferma(_ t: Turno) -> some View {
        let oggi = Calendar.current.isDateInToday(t.inizio)
        return VStack(alignment: .leading, spacing: 6) {
            Text(oggi ? "✔︎ CONFERMA IL TURNO DI OGGI" : "✔︎ CONFERMA IL TURNO DI " + formatoGiorno(t.inizio, "EEEE d").uppercased())
                .font(.footnote.bold()).foregroundStyle(.orange)
            Text("\(t.tipo.emoji) \(t.orario)").font(.title2.weight(.heavy))
            Text("pausa \(t.pausa) min · **\(oreMinuti(t.ore))** (\(centesimi(t.ore)))").foregroundStyle(.secondary)
            Text("Hai fatto queste ore?")
            HStack(spacing: 8) {
                Button { Conferme.conferma(t.inizio); aggiorna.toggle() } label: {
                    Text("✅ Sì, giusto").bold().foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppColor.fng, in: RoundedRectangle(cornerRadius: 12))
                }
                Button { modifica = CalendarioView.Giorno(id: Calendar.current.startOfDay(for: t.inizio)) } label: {
                    Text("✏️ Modifica").bold().foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppColor.sfondo, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColor.mattina, lineWidth: 2))
    }

    @ViewBuilder func cartaDomani(_ ora: Date) -> some View {
        let t = Calcoli.domani(turni, ora: ora)
        VStack(alignment: .leading, spacing: 4) {
            Text(etichetta("DOMANI")).font(.footnote.bold()).opacity(0.9)
            Text(t.map { "\($0.tipo.emoji) \($0.tipo.nome) \($0.orario)" } ?? "😴 Riposo")
                .font(.title3.weight(.heavy))
        }
        .foregroundStyle(t == nil ? Color.primary : .white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(t?.tipo.colore ?? AppColor.riposo, in: RoundedRectangle(cornerRadius: 20))
    }

    func settimana(_ ora: Date) -> some View {
        let inizio = Calcoli.inizioSettimana(ora)
        let fine = inizio.addingTimeInterval(7 * 86400)
        let sett = turni.filter { $0.inizio >= inizio && $0.inizio < fine }
        let fatte = sett.filter { $0.fine <= ora }.reduce(0) { $0 + $1.ore }
        let giorni = Set(sett.map { Calendar.current.startOfDay(for: $0.inizio) }).count
        return Riquadro {
            Text("Questa settimana").font(.headline)
            RigaOre(titolo: "Ore fatte", ore: fatte)
            RigaOre(titolo: "Ore previste", ore: sett.reduce(0) { $0 + $1.ore })
            Riga(titolo: "Mattine · Pomeriggi",
                 valore: "\(sett.filter { $0.tipo == .mattina }.count) · \(sett.filter { $0.tipo == .pomeriggio }.count)")
            Riga(titolo: "Riposi", valore: "\(7 - giorni)")
        }
    }

    var memoOggi: some View {
        let oggi = memo.filter { Calendar.current.isDateInToday($0.giorno) }
        let condivisi = stato.condivisi.flatMap { p in p.memo.filter { Calendar.current.isDateInToday($0.giorno) }.map { (p.nome, $0) } }
        return Riquadro {
            Text("📝 Memo di oggi").font(.headline)
            ForEach(condivisi, id: \.1.id) { coppia in
                let (chiLoHaScritto, m) = coppia
                HStack {
                    Image(systemName: m.fatto ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                    Text(m.testo).strikethrough(m.fatto)
                    Spacer()
                    Text("da \(chiLoHaScritto)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if oggi.isEmpty && condivisi.isEmpty {
                Text("Nessun memo").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(oggi) { m in
                HStack {
                    Image(systemName: m.fatto ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(AppColor.ardesia)
                        .onTapGesture { m.fatto.toggle() }
                    Text(m.testo).strikethrough(m.fatto)
                    Spacer()
                    if let a = m.avviso { Text("⏰ \(Turno.ora(a))").font(.subheadline) }
                }
            }
        }
    }
}

struct BottonePausa: View {
    var turno: Turno
    @State private var fatta = false

    var body: some View {
        Button {
            Pause.segna(turno.id, fatta: !fatta)
            fatta.toggle()
        } label: {
            Label(fatta ? "Pausa fatta" : "Segna la pausa come fatta", systemImage: fatta ? "checkmark.circle.fill" : "cup.and.saucer")
                .font(.subheadline.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.25), in: Capsule())
        }
        .buttonStyle(.plain)
        .onAppear { fatta = Pause.fatta(turno.id) }
    }
}

// MARK: - Calendario

struct CalendarioView: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.modelContext) var contesto
    @Query var manuali: [TurnoManuale]
    var turni: [Turno]
    var nome: String?
    @Binding var chi: String?
    @State private var mese = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!
    @State private var scelto: Giorno?

    struct Giorno: Identifiable { var id: Date }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(formatoGiorno(mese, "MMMM yyyy").capitalized).font(.largeTitle.bold())
                    Spacer()
                    Button { cambia(-1) } label: { Image(systemName: "chevron.left") }
                    Button { cambia(1) } label: { Image(systemName: "chevron.right") }.padding(.leading, 10)
                }
                SceltaPersona(chi: $chi)
                Text(nome.map { "Turni di \($0) (solo da vedere)" } ?? "Tocca un giorno per cambiare turno").foregroundStyle(.secondary)
                Riquadro {
                    LazyVGrid(columns: [GridItem(.fixed(14), spacing: 4)] + Array(repeating: GridItem(spacing: 5), count: 7), spacing: 5) {
                        Color.clear.frame(height: 1)
                        ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { i in
                            Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Calcoli.settimane(mese: mese), id: \.self) { lunedi in
                            Text("\(Calcoli.kw(lunedi))").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            // Ogni giorno ha come id la sua data, così nessuna cella si ripete.
                            ForEach((0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: lunedi)! }, id: \.self) { g in
                                cella(g)
                            }
                        }
                    }
                }
                riepilogo
                orePerSettimana
            }
            .padding(16)
        }
        .background(AppColor.sfondo)
        .sheet(item: $scelto) { g in
            SceltaTurno(giorno: g.id, dayforce: Calcoli.turno(stato.daCalendario, giorno: g.id))
                .presentationDetents([.large])
        }
    }

    func cella(_ g: Date) -> some View {
        let t = Calcoli.turno(turni, giorno: g)
        let oggi = Calendar.current.isDateInToday(g)
        let fuori = !Calendar.current.isDate(g, equalTo: mese, toGranularity: .month)
        return Button { if nome == nil { scelto = Giorno(id: g) } } label: {
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: g))").font(.subheadline.bold())
                if let t, t.assenza {
                    Text("\(t.codice ?? "")\n\(oreMinuti(t.ore))")
                        .font(.system(size: 9, weight: .semibold)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.6)
                } else if let t {
                    Text("\(Turno.ora(t.inizio))\n\(Turno.ora(t.fine))")
                        .font(.system(size: 9, weight: .semibold)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.7)
                } else {
                    Text("—\n ").font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(t == nil ? Color.primary : .white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(t.map { $0.assenza ? AppColor.fng : $0.tipo.colore } ?? AppColor.riposo, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black, lineWidth: oggi ? 2 : 0))
            .opacity(fuori ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(fuori ? "fuori-\(Calendar.current.component(.day, from: g))" : "giorno-\(Calendar.current.component(.day, from: g))")
    }

    var riepilogo: some View {
        let fine = Calendar.current.date(byAdding: .month, value: 1, to: mese)!
        let delMese = turni.filter { $0.inizio >= mese && $0.inizio < fine }
        let n = Calendar.current.range(of: .day, in: .month, for: mese)!.count
        let lavorati = Set(delMese.map { Calendar.current.startOfDay(for: $0.inizio) }).count
        return Riquadro {
            HStack {
                Text("**\(delMese.filter { $0.tipo == .mattina }.count)** M · **\(delMese.filter { $0.tipo == .pomeriggio }.count)** P · **\(n - lavorati)** R")
                Spacer()
                OreTesto(ore: Calcoli.ore(turni, da: mese, a: fine))
            }
        }
    }

    var orePerSettimana: some View {
        let settimane = Calcoli.settimane(mese: mese)
        let fngMese = settimane.filter { Calcoli.fng(turni, lunedi: $0) && Calendar.current.isDate($0.addingTimeInterval(6 * 86400), equalTo: mese, toGranularity: .month) }.count
        return Riquadro {
            Text("Ore per settimana").font(.headline)
            ForEach(settimane, id: \.self) { lunedi in
                let domenica = Calendar.current.date(byAdding: .day, value: 6, to: lunedi)!
                let fine = Calendar.current.date(byAdding: .day, value: 7, to: lunedi)!
                let ore = Calcoli.ore(turni, da: lunedi, a: fine)
                let fng = Calcoli.fng(turni, lunedi: lunedi)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(Calcoli.kw(lunedi))").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                        Text("\(formatoGiorno(lunedi, "d MMM")) – \(formatoGiorno(domenica, "d MMM"))")
                        if fng {
                            Text("FNG").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(AppColor.fng, in: RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                        OreTesto(ore: ore)
                    }
                    if !fng, ore >= Calcoli.oreContratto, Calcoli.turno(turni, giorno: domenica) != nil {
                        Text("Domenica lavorata: mancano \(oreMinuti(Calcoli.oreFNG - ore)) per l'FNG")
                            .font(.caption).foregroundStyle(.secondary).padding(.leading, 30)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 4).padding(.horizontal, fng ? 6 : 0)
                .background(fng ? AppColor.fng.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            Riga(titolo: "FNG nel mese", valore: "\(fngMese)")
            Text("L'FNG scatta se nella settimana lavori la domenica e fai almeno \(formatoOre(Calcoli.oreFNG)) ore pagate (senza pause).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func cambia(_ n: Int) {
        mese = Calendar.current.date(byAdding: .month, value: n, to: mese)!
    }
}

struct SceltaTurno: View {
    @Environment(\.modelContext) var contesto
    @Environment(\.dismiss) var chiudi
    @Query var manuali: [TurnoManuale]
    @AppStorage("mattinaInizio") var mI = 360
    @AppStorage("mattinaFine") var mF = 840
    @AppStorage("pomeriggioInizio") var pI = 840
    @AppStorage("pomeriggioFine") var pF = 1320
    var giorno: Date
    /// Il turno di Dayforce di quel giorno, se c'è.
    var dayforce: Turno?

    @State private var riposo = false
    @State private var inizio = Date.now
    @State private var fine = Date.now
    @State private var pausa = Turno.pausaMinima
    @State private var pronto = false

    var fineVera: Date { fine > inizio ? fine : fine.addingTimeInterval(86400) }
    var anteprima: Turno { Turno(id: "x", inizio: inizio, fine: fineVera, pausaMin: pausa) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(formatoGiorno(giorno, "EEEE d MMMM").capitalized).font(.title2.bold())
                HStack(spacing: 8) {
                    bottone("☀️ Mattina", AppColor.mattina, .white, scelto: !riposo && anteprima.tipo == .mattina) { imposta(mI, mF) }
                    bottone("🌙 Pomeriggio", AppColor.pomeriggio, .white, scelto: !riposo && anteprima.tipo == .pomeriggio) { imposta(pI, pF) }
                    bottone("😴 Riposo", AppColor.riposo, .primary, scelto: riposo) { riposo = true }
                }
                if !riposo {
                    Riquadro {
                        DatePicker("Inizio", selection: $inizio, displayedComponents: .hourAndMinute)
                        Divider()
                        HStack {
                            DatePicker(selection: $fine, displayedComponents: .hourAndMinute) {
                                HStack(spacing: 6) {
                                    Text("Fine")
                                    if let extra = straordinario { Text(extra).font(.caption.bold()).foregroundStyle(.orange) }
                                }
                            }
                        }
                        Divider()
                        Stepper("Pausa (non pagata): \(pausa) min", value: $pausa, in: Turno.pausaMinima...180, step: 1)
                        Divider()
                        Riga(titolo: "Ore pagate", valore: durata(anteprima.ore * 3600))
                    }
                }
                Text(dayforce.map { "Dayforce dice \($0.orario). La modifica vale solo per questo giorno." } ?? "Nessun turno di Dayforce in questo giorno.")
                    + Text(" La pausa minima è di \(Turno.pausaMinima) minuti.")
                Button { salva() } label: {
                    Text("Salva").bold().foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppColor.ardesia, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                Button("Torna all'orario di Dayforce") { togli(); chiudi() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .font(.subheadline)
            .padding(20)
        }
        .background(AppColor.sfondo)
        .onAppear(perform: carica)
    }

    var straordinario: String? {
        guard let d = dayforce else { return nil }
        let diff = fineVera.timeIntervalSince(d.fine) + d.inizio.timeIntervalSince(inizio)
        return diff > 59 ? "+\(durata(diff)) straord." : nil
    }

    func carica() {
        guard !pronto else { return }
        pronto = true
        if let m = manuali.first(where: { Calendar.current.isDate($0.giorno, inSameDayAs: giorno) }) {
            riposo = m.riposo
            inizio = m.inizio
            fine = m.fine
            pausa = max(Turno.pausaMinima, m.pausa)
            if m.riposo { imposta(mI, mF); riposo = true }
        } else if let d = dayforce {
            inizio = d.inizio
            fine = d.fine
        } else {
            imposta(mI, mF)
        }
    }

    func imposta(_ da: Int, _ a: Int) {
        riposo = false
        inizio = data(giorno, minuti: da)
        fine = data(giorno, minuti: a > da ? a : a + 1440)
    }

    func bottone(_ t: String, _ sfondo: Color, _ testo: Color, scelto: Bool, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(t).font(.subheadline.bold()).foregroundStyle(testo)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(sfondo, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: scelto ? 3 : 0))
        }
        .buttonStyle(.plain)
    }

    func togli() {
        for m in manuali where Calendar.current.isDate(m.giorno, inSameDayAs: giorno) { contesto.delete(m) }
    }

    func salva() {
        togli()
        let m = TurnoManuale(giorno: giorno, riposo: riposo, inizio: inizio, fine: fineVera)
        m.pausa = pausa
        contesto.insert(m)
        Conferme.conferma(giorno)
        chiudi()
    }
}

struct ImportaSuperShift: View {
    @Environment(\.modelContext) var contesto
    @Environment(\.dismiss) var chiudi
    @Query var manuali: [TurnoManuale]
    var giorni: [GiornoImportato]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let conta = Dictionary(grouping: giorni, by: \.codice).mapValues(\.count)
                    ForEach(["MA", "PO", "RI", "MI", "FE", "PE"], id: \.self) { k in
                        if let n = conta[k] { Riga(titolo: SuperShift.nome(k), valore: "\(n)") }
                    }
                } header: {
                    Text("Trovati \(giorni.count) giorni · \(formatoGiorno(giorni.first!.giorno, "MMM yyyy")) – \(formatoGiorno(giorni.last!.giorno, "MMM yyyy"))")
                }
                Section("Giorni") {
                    ForEach(giorni) { g in
                        HStack {
                            Text(g.codice).font(.caption.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(SuperShift.colore(g), in: RoundedRectangle(cornerRadius: 6))
                            Text(formatoGiorno(g.giorno, "EEE d MMM") + (g.riposo ? " · Riposo" : " · \(Turno.ora(g.inizio))–\(Turno.ora(g.fine))"))
                                .font(.subheadline)
                            Spacer()
                            if !g.riposo {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(oreMinuti(g.ore)).font(.subheadline.bold())
                                    if let p = g.pausa { Text("pausa \(p) min").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importa da SuperShift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) { Button("Importa \(giorni.count)") { importa() } }
            }
        }
    }

    func importa() {
        let date = Set(giorni.map { Calendar.current.startOfDay(for: $0.giorno) })
        for m in manuali where date.contains(Calendar.current.startOfDay(for: m.giorno)) { contesto.delete(m) }
        for g in giorni {
            let m = TurnoManuale(giorno: g.giorno, riposo: g.riposo, inizio: g.inizio, fine: g.fine)
            m.pausa = g.pausa ?? Turno.pausaMinima
            m.codice = g.codice
            m.orePagate = g.riposo ? -1 : g.ore
            contesto.insert(m)
            if g.fine < .now { Conferme.conferma(g.giorno) }
        }
        chiudi()
    }
}

// MARK: - Memo

struct MemoView: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.modelContext) var contesto
    @Query(sort: \Memo.giorno) var memo: [Memo]
    @State private var nuovo = false

    var body: some View {
        NavigationStack {
            List {
                let daFare = memo.filter { !$0.fatto }
                let fatti = memo.filter(\.fatto)
                if memo.isEmpty {
                    Text("Nessun memo. Tocca + per aggiungerne uno.").foregroundStyle(.secondary)
                }
                if !daFare.isEmpty { Section("Da fare") { ForEach(daFare) { riga($0) } } }
                if !fatti.isEmpty { Section("Fatti") { ForEach(fatti) { riga($0) } } }
                ForEach(stato.condivisi.filter { !$0.memo.isEmpty }) { p in
                    Section("Da \(p.nome) (solo da vedere)") {
                        ForEach(p.memo) { m in
                            HStack {
                                Image(systemName: m.fatto ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(m.testo).strikethrough(m.fatto)
                                    Text(formatoGiorno(m.giorno, "EEE d MMM")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Memo")
            .toolbar {
                Button { nuovo = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuovo memo")
            }
            .sheet(isPresented: $nuovo) { NuovoMemo() }
        }
    }

    func riga(_ m: Memo) -> some View {
        HStack {
            Image(systemName: m.fatto ? "checkmark.circle.fill" : "circle").foregroundStyle(AppColor.ardesia)
            VStack(alignment: .leading) {
                Text(m.testo).strikethrough(m.fatto)
                Text(formatoGiorno(m.giorno, "EEE d MMM") + (m.avviso.map { " · ⏰ " + Turno.ora($0) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.fatto.toggle() }
        .swipeActions { Button("Elimina", role: .destructive) { contesto.delete(m) } }
    }
}

struct NuovoMemo: View {
    @Environment(\.modelContext) var contesto
    @Environment(\.dismiss) var chiudi
    @State private var testo = ""
    @State private var giorno = Date.now
    @State private var conAvviso = false
    @State private var ora = Date.now.addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Cosa devi ricordare?", text: $testo)
                DatePicker("Giorno", selection: $giorno, displayedComponents: .date)
                Toggle("Avvisami", isOn: $conAvviso)
                if conAvviso {
                    DatePicker("Ora", selection: $ora, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Nuovo memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: ora)
                        let avviso = conAvviso ? data(giorno, minuti: (c.hour ?? 0) * 60 + (c.minute ?? 0)) : nil
                        contesto.insert(Memo(testo: testo, giorno: giorno, avviso: avviso))
                        chiudi()
                    }
                    .disabled(testo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Ore

struct OreView: View {
    var turni: [Turno]
    @State private var perMese = false
    @State private var spostamento = 0

    var periodo: (Date, Date) {
        let c = Calendar.current
        if perMese {
            let m = c.date(from: c.dateComponents([.year, .month], from: .now))!
            let da = c.date(byAdding: .month, value: spostamento, to: m)!
            return (da, c.date(byAdding: .month, value: 1, to: da)!)
        }
        let da = c.date(byAdding: .day, value: 7 * spostamento, to: Calcoli.inizioSettimana(.now))!
        return (da, c.date(byAdding: .day, value: 7, to: da)!)
    }

    var body: some View {
        let (da, a) = periodo
        let lista = turni.filter { $0.inizio >= da && $0.inizio < a }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ore").font(.largeTitle.bold())
                Picker("", selection: $perMese) {
                    Text("Settimana").tag(false)
                    Text("Mese").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: perMese) { spostamento = 0 }
                HStack {
                    Button { spostamento -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(perMese ? formatoGiorno(da, "MMMM yyyy").capitalized
                         : "\(formatoGiorno(da, "d MMM")) – \(formatoGiorno(a.addingTimeInterval(-1), "d MMM"))")
                        .font(.headline)
                    Spacer()
                    Button { spostamento += 1 } label: { Image(systemName: "chevron.right") }
                }
                Riquadro {
                    Text(oreMinuti(Calcoli.ore(turni, da: da, a: a))).font(.system(size: 34, weight: .heavy))
                    Text(centesimi(Calcoli.ore(turni, da: da, a: a))).font(.headline).foregroundStyle(.secondary)
                    Riga(titolo: "☀️ Mattine", valore: "\(lista.filter { $0.tipo == .mattina }.count)")
                    Riga(titolo: "🌙 Pomeriggi", valore: "\(lista.filter { $0.tipo == .pomeriggio }.count)")
                }
                Riquadro {
                    if lista.isEmpty { Text("Nessun turno").foregroundStyle(.secondary) }
                    ForEach(lista) { t in
                        HStack {
                            Text(formatoGiorno(t.inizio, "EEE d").capitalized)
                            Spacer()
                            Text(t.orario).font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(t.tipo.colore, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppColor.sfondo)
    }
}

// MARK: - Altro

struct AltroView: View {
    @EnvironmentObject var stato: Stato
    var turni: [Turno]
    @AppStorage("nome") var nome = ""
    @AppStorage("condividiTurni") var condividiTurni = false
    @AppStorage("condividiMemo") var condividiMemo = false
    @State private var errore: String?
    @State private var scegliPDF = false
    @State private var importati: [GiornoImportato] = []
    @State private var anteprima = false
    @AppStorage("mattinaInizio") var mI = 360
    @AppStorage("mattinaFine") var mF = 840
    @AppStorage("pomeriggioInizio") var pI = 840
    @AppStorage("pomeriggioFine") var pF = 1320

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if stato.accesso {
                        ForEach(stato.calendari, id: \.calendarIdentifier) { cal in
                            Toggle(cal.title, isOn: Binding(
                                get: { stato.scelti.contains(cal.calendarIdentifier) },
                                set: { on in
                                    stato.scelti.removeAll { $0 == cal.calendarIdentifier }
                                    if on { stato.scelti.append(cal.calendarIdentifier) }
                                }))
                        }
                    } else {
                        Button("Collega il calendario") { Task { await stato.chiediAccesso() } }
                    }
                } header: {
                    Text("Turni da Dayforce")
                } footer: {
                    Text("Accendi il calendario dove Dayforce copia i turni. L'app prende gli orari esatti: se il turno inizia prima delle 12 è una mattina, altrimenti un pomeriggio.")
                }

                Section {
                    TextField("Il tuo nome (es. Salvo)", text: $nome)
                    Toggle("Condividi i turni", isOn: attiva($condividiTurni))
                    Toggle("Condividi i memo", isOn: attiva($condividiMemo))
                    if let c = stato.calendarioMio, condividiTurni || condividiMemo {
                        Riga(titolo: "Calendario", valore: "“\(c.title)”")
                    }
                    if let e = errore { Text(e).foregroundStyle(.red) }
                } header: {
                    Text("Condivisione")
                } footer: {
                    Text("L'app scrive turni e/o memo nel calendario iCloud “Turni \(nome.isEmpty ? "<nome>" : nome)”. Per farlo vedere a un'altra persona: app Calendario › Calendari › ⓘ accanto al calendario › Aggiungi persona › la sua email iCloud, togliendo “Consenti modifiche”. Lei accetta l'invito e lo accende qui sotto, nella sua app.")
                }

                Section {
                    if stato.calendariDiAltri.isEmpty {
                        Text(stato.accesso ? "Nessun calendario “Turni …” condiviso con te." : "Prima collega il calendario.").foregroundStyle(.secondary)
                    }
                    ForEach(stato.calendariDiAltri, id: \.calendarIdentifier) { cal in
                        Toggle(cal.title, isOn: Binding(
                            get: { stato.seguiti.contains(cal.calendarIdentifier) },
                            set: { on in
                                var s = stato.seguiti.filter { $0 != cal.calendarIdentifier }
                                if on { s.append(cal.calendarIdentifier) }
                                stato.seguiti = s
                            }))
                    }
                } header: {
                    Text("Condivisi con te")
                }

                Section {
                    Button("Importa PDF da SuperShift") { scegliPDF = true }
                } header: {
                    Text("Turni passati")
                } footer: {
                    Text("In SuperShift esporta gli orari in PDF e salvalo in File. Gli orari importati (con pause e ore pagate) sostituiscono quelli di Dayforce in quei giorni.")
                }

                Section {
                    orario("Mattina inizio", $mI)
                    orario("Mattina fine", $mF)
                    orario("Pomeriggio inizio", $pI)
                    orario("Pomeriggio fine", $pF)
                } header: {
                    Text("Orari dei turni segnati a mano")
                }

                Section {
                    Button("Mostra ora il conto alla rovescia") {
                        ContoAllaRovescia.aggiorna(turni, memo: nil)
                    }
                } header: {
                    Text("Schermata di blocco")
                } footer: {
                    Text("Il conto alla rovescia compare da solo quando apri l'app durante il turno o nelle 3 ore prima. All'inizio del turno ti arriva un avviso: toccalo e parte. Puoi anche aggiungere il widget \"Turni\" alla schermata di blocco: mostra il turno di domani e quanto manca alla fine.")
                }

                Section {
                    Riga(titolo: "Versione", valore: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Altro")
            .fileImporter(isPresented: $scegliPDF, allowedContentTypes: [.pdf]) { esito in
                guard case .success(let url) = esito else { return }
                let accesso = url.startAccessingSecurityScopedResource()
                defer { if accesso { url.stopAccessingSecurityScopedResource() } }
                importati = SuperShift.leggi(SuperShift.testo(pdf: url) ?? "")
                if importati.isEmpty { errore = "Nel PDF non ho trovato orari di SuperShift." } else { anteprima = true }
            }
            .sheet(isPresented: $anteprima) { ImportaSuperShift(giorni: importati) }
        }
    }

    /// Accende la condivisione solo se c'è il nome e il calendario si può creare.
    func attiva(_ valore: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { valore.wrappedValue }, set: { on in
            errore = nil
            guard on else { valore.wrappedValue = false; return }
            let n = nome.trimmingCharacters(in: .whitespaces)
            guard stato.accesso else { errore = "Prima collega il calendario (sezione Turni da Dayforce)."; return }
            guard !n.isEmpty else { errore = "Scrivi prima il tuo nome."; return }
            do {
                _ = try stato.creaCalendario(nome: n)
                valore.wrappedValue = true
                NotificationCenter.default.post(name: .condivisioneCambiata, object: nil)
            } catch {
                errore = "Non riesco a creare il calendario: \(error.localizedDescription)"
            }
        })
    }

    func orario(_ titolo: String, _ minuti: Binding<Int>) -> some View {
        DatePicker(titolo, selection: Binding(
            get: { data(.now, minuti: minuti.wrappedValue) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minuti.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
    }
}
