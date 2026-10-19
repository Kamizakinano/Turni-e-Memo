# Turni: istruzioni per Claude

App iOS per i turni di lavoro (mattina/pomeriggio) presi da Dayforce tramite il Calendario dell'iPhone, con memo e conto alla rovescia sulla schermata di blocco. SwiftUI, SwiftData, iOS 17+. L'utente la installa con Sideloadly e non programma: rispondi in italiano, in breve, con anteprime delle schermate (iPhone con Dynamic Island) prima di ogni modifica, e parti solo quando scrive "parti".

- Versione in `project.yml` (`MARKETING_VERSION`, due punti: app e widget).
- Il push su `claude/**` avvia la CI (macOS): prove sul simulatore, poi l'IPA nella release `ultima-versione`. Mai mandare un'IPA se le prove falliscono.
- `Shared/Turni.swift`: `Turno`, `Calcoli`, `Archivio` (condivisi col widget). `Turni/Sincronizza.swift`: lettura calendario, conto alla rovescia (Live Activity), avvisi. `Turni/ContentView.swift`: schede Oggi, Calendario, Memo, Ore, Altro. `TurniWidget/`: widget schermata di blocco e Live Activity.
