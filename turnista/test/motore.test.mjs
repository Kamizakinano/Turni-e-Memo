import test from 'node:test';
import assert from 'node:assert/strict';
import { genera, regoleBase, verifica, suggerimenti, oreSettimana, coperture, oreGiorno, accorcia, preferenze } from '../motore.js';

// 25 dipendenti di esempio (nomi inventati): 5 responsabili, contratti da 40, 30 e 20 ore.
export function esempio() {
  const abil = ['frutta', 'pane', 'commissionamento', 'cassa'];
  return Array.from({ length: 25 }, (_, i) => ({
    id: 'd' + i, nome: 'Persona ' + (i + 1), resp: i < 5,
    ore: i === 23 || i === 24 ? 20 : i % 3 === 0 ? 30 : 40,
    abilita: [abil[i % 4], 'cassa'],
  }));
}

test('la settimana rispetta tutte le regole', () => {
  const dip = esempio(), r = regoleBase();
  const { piano, scoperti } = genera(dip, r);
  assert.deepEqual(scoperti, []);
  const v = verifica(piano, dip, r);
  assert.deepEqual(v.errori, []);
  for (let g = 0; g < 7; g++) {
    const c = coperture(piano[g], dip, r);
    assert.ok(c.apertura >= 4 && c.chiusura >= 4 && c.cambio >= 2 && c.respCambio, 'giorno ' + g);
  }
  for (const d of dip) assert.ok(piano.filter(x => x[d.id]).length <= 6);
});

test('lo straordinario è il minimo possibile', () => {
  const dip = esempio(), r = regoleBase();
  const { piano } = genera(dip, r);
  const v = verifica(piano, dip, r);
  console.log('straordinario', v.straordinario, 'ore per giorno', piano.map(g => oreGiorno(g, r)));
  assert.ok(v.straordinario <= 8, 'straordinario ' + v.straordinario);
});

test('le richieste vengono rispettate', () => {
  const dip = esempio(), r = regoleBase();
  const richieste = [{ dip: 'd0', giorno: 0, tipo: 'ferie' }, { dip: 'd0', giorno: 1, tipo: 'ferie' },
                     { dip: 'd6', giorno: 3, tipo: 'non disponibile', da: 840, a: 1440 }];
  const { piano } = genera(dip, r, richieste);
  assert.equal(piano[0].d0, undefined);
  assert.equal(piano[1].d0, undefined);
  assert.ok(!piano[3].d6 || piano[3].d6.fine <= 840);
  assert.deepEqual(verifica(piano, dip, r, richieste).errori, []);
});

test('la rotazione cambia fascia la settimana dopo', () => {
  const dip = esempio(), r = regoleBase();
  const s1 = genera(dip, r, [], null, 0).piano;
  const s2 = genera(dip, r, [], s1, 1).piano;
  const pref = preferenze(dip, s1);
  let cambiati = 0, totale = 0;
  for (const d of dip) {
    const prima = s1.filter(x => x[d.id]?.fascia === 'M').length > s1.filter(x => x[d.id]?.fascia === 'P').length ? 'M' : 'P';
    const dopo = s2.filter(x => x[d.id]?.fascia === 'M').length > s2.filter(x => x[d.id]?.fascia === 'P').length ? 'M' : 'P';
    totale++; if (prima !== dopo) cambiati++;
  }
  console.log('cambiano fascia', cambiati, 'su', totale);
  assert.ok(cambiati >= totale * 0.6);
  assert.deepEqual(verifica(s2, dip, r, [], s1).errori, []);
});

test('monte ore superato: i tagli rispettano apertura e chiusura', () => {
  const dip = esempio(), r = regoleBase();
  r.monteOre[2] = 80;
  const { piano } = genera(dip, r);
  const s = suggerimenti(piano, dip, r, 2);
  assert.ok(s.length > 0);
  for (const x of s) piano[2][x.id] = x.dopo;
  console.log('mercoledì dopo i tagli', oreGiorno(piano[2], r), s.map(x => x.modo));
  const c = coperture(piano[2], dip, r);
  assert.ok(c.ok);
  // prima entrano più tardi, poi escono prima
  assert.ok(s.every(x => x.modo === 'tardi') || s.findIndex(x => x.modo === 'prima') > 0);
});
