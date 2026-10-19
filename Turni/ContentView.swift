import SwiftUI
import SwiftData
import EventKit

struct ContentView: View {
    @EnvironmentObject var stato: Stato
    @Query var manuali: [TurnoManuale]
    @Query(sort: \Memo.giorno) var memo: [Memo]
    @Environment(\.scenePhase) var fase

    var turni: [Turno] {
        Calcoli.unisci(dalCalendario: stato.daCalendario,
                       manuali: manuali.filter { !$0.riposo }.map(\.turno),
                       riposi: manuali.filter(\.riposo).map(\.giorno))
    }

    var body: some View {
        TabView {
            OggiView(turni: turni)
                .tabItem { Label("Oggi", systemImage: "sun.max.fill") }
            CalendarioView(turni: turni)
                .tabItem { Label("Calendario", systemImage: "calendar") }
            MemoView()
                .tabItem { Label("Memo", systemImage: "note.text") }
            OreView(turni: turni)
                .tabItem { Label("Ore", systemImage: "clock") }
            AltroView(turni: turni)
                .tabItem { Label("Altro", systemImage: "gearshape") }
        }
        .tint(AppColor.ardesia)
        .onAppear { stato.leggi(); pubblica() }
        .onChange(of: turni) { pubblica() }
        .onChange(of: memo.map(\.testo)) { pubblica() }
        .onChange(of: fase) { if fase == .active { stato.leggi(); pubblica() } }
    }

    func pubblica() {
        let oggi = memo.first { !$0.fatto && Calendar.current.isDateInToday($0.giorno) }?.testo
        let avvisi = memo.compactMap { m in m.fatto ? nil : m.avviso.map { (m.uid, m.testo, $0) } }
        stato.pubblica(turni, memoOggi: oggi, memo: avvisi)
    }
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let ora = ctx.date
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Oggi").font(.largeTitle.bold())
                        Text(formatoGiorno(ora, "EEEE d MMMM").capitalized).foregroundStyle(.secondary)
                    }
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
                    cartaDomani(ora)
                    settimana(ora)
                    memoOggi
                }
                .padding(16)
            }
            .background(AppColor.sfondo)
        }
    }

    @ViewBuilder func cartaOggi(_ ora: Date) -> some View {
        let t = Calcoli.inCorso(turni, ora: ora) ?? Calcoli.turno(turni, giorno: ora)
        VStack(alignment: .leading, spacing: 4) {
            Text(t.map { Calcoli.inCorso(turni, ora: ora) == $0 ? "TURNO IN CORSO" : "TURNO DI OGGI" } ?? "OGGI")
                .font(.footnote.bold()).opacity(0.9)
            if let t {
                Text("\(t.tipo.emoji) \(t.tipo.nome)").font(.system(size: 30, weight: .heavy))
                Text("\(t.orario) · \(formatoOre(t.ore)) ore").font(.title3)
                if t.inizio <= ora && ora < t.fine {
                    Text("Mancano \(durata(t.fine.timeIntervalSince(ora)))").font(.headline)
                } else if t.fine <= ora {
                    Text("Turno finito").font(.headline)
                }
            } else {
                Text("😴 Riposo").font(.system(size: 30, weight: .heavy))
            }
        }
        .foregroundStyle(t == nil ? Color.primary : .white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(t?.tipo.colore ?? AppColor.riposo, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder func cartaDomani(_ ora: Date) -> some View {
        let t = Calcoli.domani(turni, ora: ora)
        VStack(alignment: .leading, spacing: 4) {
            Text("DOMANI").font(.footnote.bold()).opacity(0.9)
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
            Riga(titolo: "Ore fatte / previste", valore: "\(formatoOre(fatte)) / \(formatoOre(sett.reduce(0) { $0 + $1.ore }))")
            Riga(titolo: "Mattine · Pomeriggi",
                 valore: "\(sett.filter { $0.tipo == .mattina }.count) · \(sett.filter { $0.tipo == .pomeriggio }.count)")
            Riga(titolo: "Riposi", valore: "\(7 - giorni)")
        }
    }

    var memoOggi: some View {
        let oggi = memo.filter { Calendar.current.isDateInToday($0.giorno) }
        return Riquadro {
            Text("📝 Memo di oggi").font(.headline)
            if oggi.isEmpty {
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

// MARK: - Calendario

struct CalendarioView: View {
    @Environment(\.modelContext) var contesto
    @Query var manuali: [TurnoManuale]
    var turni: [Turno]
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
                Text("Tocca un giorno per cambiare turno").foregroundStyle(.secondary)
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
            SceltaTurno(giorno: g.id).presentationDetents([.height(330)])
        }
    }

    func cella(_ g: Date) -> some View {
        let t = Calcoli.turno(turni, giorno: g)
        let oggi = Calendar.current.isDateInToday(g)
        let fuori = !Calendar.current.isDate(g, equalTo: mese, toGranularity: .month)
        return Button { scelto = Giorno(id: g) } label: {
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: g))").font(.subheadline.bold())
                Text(t.map { $0.tipo == .mattina ? "MAT" : "POM" } ?? "—").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(t == nil ? Color.primary : .white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(t?.tipo.colore ?? AppColor.riposo, in: RoundedRectangle(cornerRadius: 9))
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
                Text("\(formatoOre(Calcoli.ore(turni, da: mese, a: fine))) h").bold()
            }
        }
    }

    var orePerSettimana: some View {
        Riquadro {
            Text("Ore per settimana").font(.headline)
            ForEach(Calcoli.settimane(mese: mese), id: \.self) { lunedi in
                let domenica = Calendar.current.date(byAdding: .day, value: 6, to: lunedi)!
                let fine = Calendar.current.date(byAdding: .day, value: 7, to: lunedi)!
                HStack {
                    Text("\(Calcoli.kw(lunedi))").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                    Text("\(formatoGiorno(lunedi, "d MMM")) – \(formatoGiorno(domenica, "d MMM"))")
                    Spacer()
                    Text("\(formatoOre(Calcoli.ore(turni, da: lunedi, a: fine))) h").bold()
                }
                .font(.subheadline)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(formatoGiorno(giorno, "EEEE d MMMM").capitalized).font(.title2.bold())
            HStack(spacing: 8) {
                bottone("☀️ Mattina", AppColor.mattina, .white) { metti(riposo: false, mI, mF) }
                bottone("🌙 Pomeriggio", AppColor.pomeriggio, .white) { metti(riposo: false, pI, pF) }
                bottone("😴 Riposo", AppColor.riposo, .primary) { metti(riposo: true, 0, 0) }
            }
            Button("Usa l'orario di Dayforce") { togli(); chiudi() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.sfondo, in: RoundedRectangle(cornerRadius: 12))
            Text("Il turno segnato a mano vale al posto di quello di Dayforce per questo giorno. Gli orari si cambiano in Altro.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    func bottone(_ t: String, _ sfondo: Color, _ testo: Color, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(t).font(.subheadline.bold()).foregroundStyle(testo)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(sfondo, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    func togli() {
        for m in manuali where Calendar.current.isDate(m.giorno, inSameDayAs: giorno) { contesto.delete(m) }
    }

    func metti(riposo: Bool, _ inizio: Int, _ fine: Int) {
        togli()
        let f = fine > inizio ? fine : fine + 1440
        contesto.insert(TurnoManuale(giorno: giorno, riposo: riposo, inizio: data(giorno, minuti: inizio), fine: data(giorno, minuti: f)))
        chiudi()
    }
}

// MARK: - Memo

struct MemoView: View {
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
                    Text("\(formatoOre(Calcoli.ore(turni, da: da, a: a))) ore").font(.system(size: 34, weight: .heavy))
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
        }
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
