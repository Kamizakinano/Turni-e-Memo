import Foundation
import PDFKit
import SwiftUI

// Importa gli orari dal PDF esportato da SuperShift.
// Ogni giorno ha una riga così: "1 Sab MA 05 20 - 14 29 11 00, 15 min 8 h 54 min Mattina"
// (giorno, tipo, orario vero, inizio e minuti della pausa, ore pagate). Le altre righe del PDF si ignorano.
struct GiornoImportato: Hashable, Identifiable {
    var giorno: Date
    var codice: String          // MA, PO, RI, MI, FE, PE
    var inizio: Date
    var fine: Date
    var pausa: Int?
    var ore: Double
    var id: Date { giorno }
    var riposo: Bool { codice == "RI" }
}

enum SuperShift {
    static let mesi = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio",
                       "agosto", "settembre", "ottobre", "novembre", "dicembre"]
    static let settimana = ["Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"]   // come Calendar.weekday (1 = domenica)

    static func nome(_ codice: String) -> String {
        ["MA": "☀️ Mattine", "PO": "🌙 Pomeriggi", "RI": "😴 Riposi", "MI": "🚗 Missioni", "FE": "🎉 Festività", "PE": "📄 Permessi"][codice] ?? codice
    }

    static func colore(_ g: GiornoImportato) -> Color {
        switch g.codice {
        case "RI": return AppColor.riposo
        case "FE", "PE": return AppColor.fng
        case "MI": return .purple
        default: return TipoTurno.da(inizio: g.inizio).colore
        }
    }

    static func testo(pdf url: URL) -> String? {
        PDFDocument(url: url)?.string
    }

    /// Legge il testo del PDF. Funziona anche se le colonne arrivano in ordine diverso (es. "05 : 20" o la pausa dopo le ore):
    /// per ogni giorno prende il primo orario, la prima pausa e le prime ore che trova prima del giorno dopo.
    static func leggi(_ testo: String, calendario c: Calendar = .current) -> [GiornoImportato] {
        let intestazioni = "(" + mesi.joined(separator: "|") + ")\\s+(20\\d\\d)|(\\d{1,2})\\s+(Lun|Mar|Mer|Gio|Ven|Sab|Dom)\\s+(MA|PO|RI|MI|FE|PE)\\b"
        guard let reH = try? NSRegularExpression(pattern: intestazioni),
              let reOrario = try? NSRegularExpression(pattern: "(\\d{2})\\s*:?\\s*(\\d{2})\\s*-\\s*(\\d{2})\\s*:?\\s*(\\d{2})"),
              let reOre = try? NSRegularExpression(pattern: "(\\d+)\\s*h(?:\\s*(\\d+)\\s*min)?"),
              let rePausa = try? NSRegularExpression(pattern: "(\\d{2})\\s*:?\\s*(\\d{2}),\\s*(\\d+)\\s*min") else { return [] }
        let ns = testo as NSString
        let tutte = reH.matches(in: testo, range: NSRange(location: 0, length: ns.length))
        var anno = 0, numMese = 0, ultimoGiorno = 0
        var risultato: [GiornoImportato] = []

        func n(_ m: NSTextCheckingResult?, _ i: Int) -> Int? {
            guard let m, m.range(at: i).location != NSNotFound else { return nil }
            return Int(ns.substring(with: m.range(at: i)))
        }

        for (i, m) in tutte.enumerated() {
            if m.range(at: 1).location != NSNotFound {
                // Intestazione del mese, es. "novembre 2025".
                numMese = (mesi.firstIndex(of: ns.substring(with: m.range(at: 1)).lowercased()) ?? 0) + 1
                anno = n(m, 2) ?? anno
                ultimoGiorno = 0
                continue
            }
            guard anno > 0, let g = n(m, 3) else { continue }
            let nomeGiorno = ns.substring(with: m.range(at: 4))
            let codice = ns.substring(with: m.range(at: 5))
            // Se il numero del giorno torna indietro senza intestazione, è il mese dopo.
            if g < ultimoGiorno { numMese += 1; if numMese > 12 { numMese = 1; anno += 1 } }
            ultimoGiorno = g
            guard var data = c.date(from: DateComponents(year: anno, month: numMese, day: g)) else { continue }
            // Controllo con il giorno della settimana; se non torna prova il mese dopo.
            if settimana[c.component(.weekday, from: data) - 1] != nomeGiorno,
               let dopo = c.date(byAdding: .month, value: 1, to: data),
               settimana[c.component(.weekday, from: dopo) - 1] == nomeGiorno {
                data = dopo
            }
            // Il pezzo di testo di questo giorno, fino all'intestazione successiva.
            let fineBlocco = i + 1 < tutte.count ? tutte[i + 1].range.location : ns.length
            let blocco = NSRange(location: m.range.upperBound, length: fineBlocco - m.range.upperBound)
            let orario = reOrario.firstMatch(in: testo, range: blocco)
            let ore = reOre.firstMatch(in: testo, range: blocco)
            let pausa = rePausa.firstMatch(in: testo, range: blocco)

            let inizio = c.date(byAdding: .minute, value: (n(orario, 1) ?? 0) * 60 + (n(orario, 2) ?? 0), to: data)!
            var fine = c.date(byAdding: .minute, value: (n(orario, 3) ?? 0) * 60 + (n(orario, 4) ?? 0), to: data)!
            if fine <= inizio && codice != "RI" { fine = c.date(byAdding: .day, value: 1, to: fine)! }
            let orePagate = Double(n(ore, 1) ?? 0) + Double(n(ore, 2) ?? 0) / 60
            risultato.append(GiornoImportato(giorno: data, codice: codice, inizio: inizio, fine: fine,
                                             pausa: n(pausa, 3), ore: codice == "RI" ? 0 : orePagate))
        }
        // Un giorno compare una volta sola.
        var visti = Set<Date>()
        return risultato.filter { visti.insert($0.giorno).inserted }
    }
}
