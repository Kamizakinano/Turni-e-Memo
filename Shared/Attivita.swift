import Foundation
import ActivityKit

// Il conto alla rovescia sulla schermata di blocco (Attività in tempo reale).
struct TurnoAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var inizio: Date
        var fine: Date
        var memo: String?
    }
    var tipo: String
}
