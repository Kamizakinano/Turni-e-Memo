// Turnista: il "motore" che crea i turni della settimana e controlla le regole.
// Orari in minuti dalla mezzanotte (05:00 = 300, 21:30 = 1290).

export const GIORNI = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
export const FASCE = { M: 'Mattina', I: 'Intermedio', P: 'Pomeriggio' };

export function regoleBase() {
  return {
    fasce: { M: { inizio: 300, fine: 810 }, I: { inizio: 540, fine: 1020 }, P: { inizio: 780, fine: 1290 } },
    pausa: 30, pausaSopra: 360,          // 30 min di pausa non pagata nei turni più lunghi di 6 ore
    fabbisogno: [
      { M: 5, I: 1, P: 5 }, { M: 4, I: 1, P: 4 }, { M: 6, I: 1, P: 6 }, { M: 5, I: 1, P: 5 },
      { M: 5, I: 1, P: 5 }, { M: 5, I: 1, P: 5 }, { M: 6, I: 1, P: 6 },
    ],
    monteOre: [90, 72, 96, 90, 90, 90, 96],
    minApertura: 4, minChiusura: 4,
    cambio: { da: 780, a: 810, min: 2 },  // al cambio turno almeno 2 persone, con un responsabile
    maxGiorni: 6, stacco: 660, durataMin: 240, passo: 30,
  };
}

export const ora = m => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

export function orePagate(t, r) {
  if (!t) return 0;
  const s = t.fine - t.inizio;
  return (s - (s > r.pausaSopra ? r.pausa : 0)) / 60;
}

// Il turno occupa questi minuti nella settimana (per lo stacco di 11 ore tra un giorno e l'altro).
const assoluto = (g, t) => ({ da: g * 1440 + t.inizio, a: g * 1440 + t.fine });

function indisponibile(richieste, id, g, t) {
  return richieste.some(q => q.dip === id && q.giorno === g &&
    (q.tipo === 'ferie' || q.tipo === 'permesso' && !q.da || (q.da ?? 0) < t.fine && (q.a ?? 1440) > t.inizio));
}

/// Ore della settimana di una persona.
export function oreSettimana(piano, id, r) {
  return piano.reduce((s, giorno) => s + orePagate(giorno[id], r), 0);
}

function rispettaStacco(piano, id, g, t, r, precedente) {
  const io = assoluto(g, t);
  const vicini = [];
  if (g > 0 && piano[g - 1][id]) vicini.push(assoluto(g - 1, piano[g - 1][id]));
  if (g < 6 && piano[g + 1][id]) vicini.push(assoluto(g + 1, piano[g + 1][id]));
  if (g === 0 && precedente?.[6]?.[id]) vicini.push(assoluto(-1, precedente[6][id]));
  return vicini.every(v => v.a + r.stacco <= io.da || io.a + r.stacco <= v.da);
}

/// Fascia preferita per la rotazione: chi la settimana prima ha fatto più mattine ora va di pomeriggio, e viceversa.
export function preferenze(dipendenti, precedente, numeroSettimana = 0) {
  const pref = {};
  dipendenti.forEach((d, i) => {
    let m = 0, p = 0;
    for (const giorno of precedente ?? []) {
      const t = giorno?.[d.id];
      if (t?.fascia === 'M') m++;
      if (t?.fascia === 'P') p++;
    }
    pref[d.id] = m > p ? 'P' : p > m ? 'M' : ((i + numeroSettimana) % 2 === 0 ? 'M' : 'P');
  });
  return pref;
}

/// Crea la settimana: un turno per posto richiesto, rispettando tutte le regole.
export function genera(dipendenti, r, richieste = [], precedente = null, numeroSettimana = 0) {
  const piano = Array.from({ length: 7 }, () => ({}));
  const pref = preferenze(dipendenti, precedente, numeroSettimana);
  const giorniFatti = Object.fromEntries(dipendenti.map(d => [d.id, 0]));
  const obiettivo = Object.fromEntries(dipendenti.map(d =>
    [d.id, Math.min(r.maxGiorni, Math.max(1, Math.round((d.ore ?? 40) / 8)))]));
  const scoperti = [];

  // Prima i giorni più pieni (mercoledì e domenica), poi gli altri.
  const ordine = [0, 1, 2, 3, 4, 5, 6].sort((a, b) => totale(r.fabbisogno[b]) - totale(r.fabbisogno[a]) || a - b);

  for (let passo = 0; passo < 2; passo++) {           // al secondo giro si accetta di superare i giorni previsti
    for (const g of ordine) {
      for (const fascia of ['M', 'P', 'I']) {
        const serve = r.fabbisogno[g][fascia] ?? 0;
        while (contaFascia(piano[g], fascia) < serve) {
          const t = { fascia, inizio: r.fasce[fascia].inizio, fine: r.fasce[fascia].fine };
          const serveResp = fascia !== 'I' && !Object.entries(piano[g]).some(([id, x]) =>
            x.fascia === fascia && dipendenti.find(d => d.id === id)?.resp);
          const scelto = migliore(dipendenti, piano, g, t, r, richieste, precedente, pref, giorniFatti, obiettivo,
                                  passo === 1, serveResp);
          if (!scelto) break;
          piano[g][scelto.id] = t;
          giorniFatti[scelto.id]++;
        }
      }
    }
  }
  for (let g = 0; g < 7; g++)
    for (const fascia of ['M', 'I', 'P']) {
      const manca = (r.fabbisogno[g][fascia] ?? 0) - contaFascia(piano[g], fascia);
      if (manca > 0) scoperti.push({ giorno: g, fascia, manca });
    }
  riempi(piano, dipendenti, r, richieste, precedente, pref);
  equilibra(piano, dipendenti, r);
  return { piano, scoperti };
}

const totale = f => (f.M ?? 0) + (f.I ?? 0) + (f.P ?? 0);
const contaFascia = (giorno, fascia) => Object.values(giorno).filter(t => t.fascia === fascia).length;

function migliore(dipendenti, piano, g, t, r, richieste, precedente, pref, giorniFatti, obiettivo, oltre, serveResp) {
  let meglio = null, punti = -Infinity;
  const abilitaPresenti = new Set(Object.entries(piano[g]).filter(([, x]) => x.fascia === t.fascia)
    .flatMap(([id]) => dipendenti.find(d => d.id === id)?.abilita ?? []));
  for (const d of dipendenti) {
    if (piano[g][d.id]) continue;
    if (serveResp && !d.resp) continue;
    if (indisponibile(richieste, d.id, g, t)) continue;
    const limite = oltre ? r.maxGiorni : obiettivo[d.id];
    if (giorniFatti[d.id] >= limite) continue;
    if (!rispettaStacco(piano, d.id, g, t, r, precedente)) continue;
    let p = 0;
    if (pref[d.id] === t.fascia || t.fascia === 'I') p += 10;
    p += (obiettivo[d.id] - giorniFatti[d.id]) * 4;          // prima chi deve ancora fare più giorni
    if (!serveResp && d.resp) p -= 3;                         // i responsabili servono dove manca un responsabile
    p += (d.abilita ?? []).filter(a => !abilitaPresenti.has(a)).length * 2;  // varietà di mansioni nel turno
    if (p > punti) { punti = p; meglio = d; }
  }
  return meglio;
}

// Chi ha ancora ore di contratto da fare viene aggiunto come rinforzo nei giorni dove il monte ore lo permette.
function riempi(piano, dipendenti, r, richieste, precedente, pref) {
  const mancanti = d => (d.ore ?? 40) - oreSettimana(piano, d.id, r);
  for (let giro = 0; giro < 7; giro++) {
    const daFare = dipendenti.filter(d => mancanti(d) >= r.durataMin / 60).sort((a, b) => mancanti(b) - mancanti(a));
    if (!daFare.length) return;
    let aggiunto = false;
    for (const d of daFare) {
      // Giorni con più spazio nel monte ore per primi.
      const giorni = [0, 1, 2, 3, 4, 5, 6].filter(g => !piano[g][d.id] && piano.filter(x => x[d.id]).length < r.maxGiorni)
        .sort((a, b) => (r.monteOre[b] - oreGiorno(piano[b], r)) - (r.monteOre[a] - oreGiorno(piano[a], r)));
      for (const g of giorni) {
        const spazio = Math.min(r.monteOre[g] - oreGiorno(piano[g], r), mancanti(d), 8);
        if (spazio < r.durataMin / 60) continue;
        for (const fascia of [pref[d.id], pref[d.id] === 'M' ? 'P' : 'M']) {
          const base = r.fasce[fascia];
          // Il rinforzo entra più tardi: il turno finisce all'ora normale e dura quanto serve.
          let t = { fascia, inizio: base.inizio, fine: base.fine };
          while (orePagate(t, r) > spazio + 0.01 && t.fine - t.inizio - r.passo >= r.durataMin)
            t = { ...t, inizio: t.inizio + r.passo };
          if (orePagate(t, r) > spazio + 0.01) continue;
          if (indisponibile(richieste, d.id, g, t) || !rispettaStacco(piano, d.id, g, t, r, precedente)) continue;
          piano[g][d.id] = t;
          aggiunto = true;
          break;
        }
        if (piano[g][d.id]) break;
      }
    }
    if (!aggiunto) return;
  }
}

/// Chi deve ancora fare ore (sotto contratto) e chi ne ha in più.
export function bilancio(piano, dipendenti, r) {
  return dipendenti.map(d => ({ id: d.id, nome: d.nome, contratto: d.ore ?? 40, fatte: oreSettimana(piano, d.id, r) }))
    .map(x => ({ ...x, differenza: x.fatte - x.contratto }));
}

// Chi supera le ore del contratto entra più tardi (o, se serve, esce prima) finché è in pari.
function equilibra(piano, dipendenti, r) {
  for (const d of dipendenti) {
    let troppo = oreSettimana(piano, d.id, r) - (d.ore ?? 40);
    for (let g = 0; g < 7 && troppo > 0.01; g++) {
      while (troppo > 0.01) {
        const s = accorcia(piano, dipendenti, g, d.id, r, Math.min(troppo * 60, 600));
        if (!s) break;
        troppo -= s.ore;
        piano[g][d.id] = s.dopo;
      }
    }
  }
}

/// Prova ad accorciare il turno di una persona di al massimo `minuti`, rispettando apertura, chiusura e cambio turno.
/// Prima fa entrare più tardi; solo se non si può fa uscire prima.
export function accorcia(piano, dipendenti, g, id, r, minuti) {
  const t = piano[g][id];
  if (!t) return null;
  const passi = Math.floor(minuti / r.passo) * r.passo;
  if (passi <= 0) return null;
  for (const modo of ['tardi', 'prima']) {
    for (let m = passi; m >= r.passo; m -= r.passo) {
      const dopo = modo === 'tardi' ? { ...t, inizio: t.inizio + m } : { ...t, fine: t.fine - m };
      if (dopo.fine - dopo.inizio < r.durataMin) continue;
      const prova = { ...piano[g], [id]: dopo };
      if (!coperture(prova, dipendenti, r).ok) continue;
      const ore = orePagate(t, r) - orePagate(dopo, r);
      if (ore <= 0) continue;
      return { giorno: g, id, prima: t, dopo, ore, modo };
    }
  }
  return null;
}

/// Apertura, chiusura e cambio turno di un giorno.
export function coperture(giorno, dipendenti, r) {
  const turni = Object.entries(giorno);
  const apertura = turni.filter(([, t]) => t.inizio <= r.fasce.M.inizio).length;
  const chiusura = turni.filter(([, t]) => t.fine >= r.fasce.P.fine).length;
  const alCambio = turni.filter(([, t]) => t.inizio <= r.cambio.da && t.fine >= r.cambio.a);
  const respCambio = alCambio.some(([id]) => dipendenti.find(d => d.id === id)?.resp);
  return {
    apertura, chiusura, cambio: alCambio.length, respCambio,
    ok: apertura >= r.minApertura && chiusura >= r.minChiusura && alCambio.length >= r.cambio.min && respCambio,
  };
}

export function oreGiorno(giorno, r) {
  return Object.values(giorno).reduce((s, t) => s + orePagate(t, r), 0);
}

/// Dove togliere ore in un giorno che supera il monte ore: prima chi è oltre il contratto, poi l'intermedio, poi gli altri.
export function suggerimenti(piano, dipendenti, r, g) {
  let troppo = oreGiorno(piano[g], r) - r.monteOre[g];
  if (troppo <= 0.01) return [];
  const prova = piano.map(x => ({ ...x }));
  const proposte = [];
  const extra = id => oreSettimana(prova, id, r) - (dipendenti.find(d => d.id === id)?.ore ?? 40);
  const ordine = Object.keys(prova[g]).sort((a, b) =>
    extra(b) - extra(a) || (prova[g][a].fascia === 'I' ? -1 : 0) - (prova[g][b].fascia === 'I' ? -1 : 0));
  for (const id of ordine) {
    if (troppo <= 0.01) break;
    const s = accorcia(prova, dipendenti, g, id, r, Math.min(troppo * 60, 240));
    if (!s) continue;
    prova[g][id] = s.dopo;
    troppo -= s.ore;
    proposte.push(s);
  }
  return proposte;
}

/// Tutti i controlli della settimana, da mostrare con ✔ o ✖.
export function verifica(piano, dipendenti, r, richieste = [], precedente = null) {
  const errori = [];
  const nome = id => dipendenti.find(d => d.id === id)?.nome ?? id;
  for (let g = 0; g < 7; g++) {
    const giorno = piano[g];
    for (const fascia of ['M', 'I', 'P']) {
      const c = contaFascia(giorno, fascia), serve = r.fabbisogno[g][fascia] ?? 0;
      if (c < serve) errori.push(`${GIORNI[g]}: ${FASCE[fascia].toLowerCase()} ${c} su ${serve}`);
      if (fascia !== 'I' && c > 0 && !Object.entries(giorno).some(([id, t]) => t.fascia === fascia && dipendenti.find(d => d.id === id)?.resp))
        errori.push(`${GIORNI[g]}: ${FASCE[fascia].toLowerCase()} senza responsabile`);
    }
    const cop = coperture(giorno, dipendenti, r);
    if (cop.apertura < r.minApertura) errori.push(`${GIORNI[g]}: solo ${cop.apertura} all'apertura`);
    if (cop.chiusura < r.minChiusura) errori.push(`${GIORNI[g]}: solo ${cop.chiusura} alla chiusura`);
    if (cop.cambio < r.cambio.min || !cop.respCambio) errori.push(`${GIORNI[g]}: cambio turno scoperto`);
    for (const [id, t] of Object.entries(giorno)) {
      if (indisponibile(richieste, id, g, t)) errori.push(`${GIORNI[g]}: ${nome(id)} ha una richiesta`);
      if (!rispettaStacco(piano, id, g, t, r, precedente)) errori.push(`${GIORNI[g]}: ${nome(id)} senza 11 ore di stacco`);
    }
  }
  for (const d of dipendenti) {
    const giorni = piano.filter(x => x[d.id]).length;
    if (giorni > r.maxGiorni) errori.push(`${d.nome}: ${giorni} giorni di lavoro`);
  }
  const straordinario = dipendenti.reduce((s, d) => s + Math.max(0, oreSettimana(piano, d.id, r) - (d.ore ?? 40)), 0);
  const sopraMonte = [0, 1, 2, 3, 4, 5, 6].filter(g => oreGiorno(piano[g], r) > r.monteOre[g] + 0.01);
  return { errori, straordinario, sopraMonte };
}
