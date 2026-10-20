# Turni: istruzioni per Claude

App iOS per i turni di lavoro (mattina/pomeriggio) presi da Dayforce tramite il Calendario dell'iPhone, con memo e conto alla rovescia sulla schermata di blocco. SwiftUI, SwiftData, iOS 17+. L'utente la installa con Sideloadly e non programma: rispondi in italiano, in breve, con anteprime delle schermate (iPhone con Dynamic Island) prima di ogni modifica, e parti solo quando scrive "parti".

- Versione in `project.yml` (`MARKETING_VERSION`, due punti: app e widget).
- Il push su `claude/**` avvia la CI (macOS): prove sul simulatore, poi l'IPA nella release `ultima-versione`. Mai mandare un'IPA se le prove falliscono.
- `Shared/Turni.swift`: `Turno`, `Calcoli`, `Archivio` (condivisi col widget). `Turni/Sincronizza.swift`: lettura calendario, conto alla rovescia (Live Activity), avvisi. `Turni/ContentView.swift`: schede Turni (oggi + calendario), Memo, Ore, Altro. `Turni/SuperShift.swift`: importazione del PDF. `TurniWidget/`: widget schermata di blocco e Live Activity.

## Regole per non sprecare il lavoro (chieste dall'utente)

- **I file dell'utente si provano interi.** Quando l'app legge un file dell'utente (PDF, calendario…), prima di mandare l'IPA controlla tutto il file vero e di' quanti elementi trova e quanti ne scarta, con il motivo.
- **Prova con i dati veri.** `TurniTests/supershift-anonimo.txt` è il PDF vero di SuperShift reso anonimo (note → "Nota N", niente nomi né luoghi): ogni modifica all'importazione deve passare `testPDFVeroAnonimo`. Il repository è **pubblico**: mai salvare dati personali.
- **Dubbio = domanda.** Se una richiesta non è chiara, chiedi prima invece di andare a tentativi.
- **Risposte brevi** e niente lavoro non richiesto.
