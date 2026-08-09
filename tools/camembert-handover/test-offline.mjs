// Serve this folder first:  python3 -m http.server 8899
// then:                     node test-offline.mjs
//
// localhost counts as a secure context, so the service worker registers here
// exactly as it will over HTTPS on a phone.
import { chromium } from 'playwright';

const URL_ = 'http://localhost:8899/index.html';
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, locale: 'fr-FR' });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE ' + m.text()); });

await page.goto(URL_);

// --- manifest + icons must be reachable and valid
const manifest = await page.evaluate(async () => {
  const href = document.querySelector('link[rel=manifest]').href;
  const r = await fetch(href);
  return { status: r.status, body: await r.json() };
});
console.log('manifest          ->', manifest.status, '|', manifest.body.name, '| icônes', manifest.body.icons.length,
  '| display', manifest.body.display);

// --- service worker takes control
await page.waitForFunction(() => navigator.serviceWorker.controller !== null, null, { timeout: 15000 });
console.log('service worker    -> actif');
const cached = await page.evaluate(async () => {
  const keys = await caches.keys();
  const c = await caches.open(keys[0]);
  return { cache: keys[0], entries: (await c.keys()).map(r => r.url.split('/').pop() || '(dossier)') };
});
console.log('cache             ->', cached.cache, '|', cached.entries.sort().join(', '));

// --- seed data, then go fully offline
for (const n of ['Marie', 'Luc', 'Anaïs']) {
  await page.fill('#newName', n);
  await page.click('.composer button[type=submit]');
}
await page.locator('.card').nth(0).locator('button.chip').click();      // payé
await page.locator('.card').nth(1).locator('.check').click();           // remis

console.log('--- RÉSEAU COUPÉ ---');
await ctx.setOffline(true);
await page.reload();
console.log('rechargement      ->', await page.title(), '| lignes',
  await page.$$eval('.card .name', e => e.map(x => x.textContent)));
console.log('états conservés   ->', await page.$$eval('.meta button.chip', e => e.map(x => x.textContent)),
  '| remis', await page.$$eval('.card.is-done', e => e.length));
console.log('créneaux          ->', await page.$$eval('.clock', e => e.map(x => x.textContent)));

// adding while offline must work
await page.fill('#newName', 'Thibault');
await page.click('.composer button[type=submit]');
await page.reload();
console.log('ajout hors ligne  ->', await page.$$eval('.card .name', e => e.map(x => x.textContent)));

// the home-screen icon opens start_url ("./"), not index.html — check it cold, offline
await page.goto('http://localhost:8899/');
console.log('start_url hors ligne ->', await page.title(), '| lignes',
  await page.$$eval('.card .name', e => e.map(x => x.textContent)));
await page.goto(URL_);

// --- backup / restore round trip
await page.click('#cfgToggle');
const backup = await page.evaluate(() => {
  const s = JSON.parse(localStorage.getItem('camembert-handover-v1'));
  return JSON.stringify({ app: 'camembert-handover', version: '2.0', savedAt: new Date().toISOString(), state: s }, null, 2);
});
console.log('sauvegarde        ->', JSON.parse(backup).state.lines.length, 'lignes,',
  backup.length, 'octets');

await page.click('#clearBtn'); await page.click('#clearBtn');
console.log('après effacement  ->', await page.$$eval('.card', e => e.length), 'lignes');

await page.click('#importBtn');
await page.fill('#importText', backup);
await page.click('#importApply');
console.log('après restauration->', await page.$$eval('.card .name', e => e.map(x => x.textContent)));
console.log('paiements         ->', await page.$$eval('.meta button.chip', e => e.map(x => x.textContent)));

// --- restoring from the plain-text list (migration path from the old app)
const pasted = [
  'File des camemberts — premier créneau 21h30, 2 par 15 min',
  '21h30  Camille — payé — remis (2 pièces) [souhait 21h30]',
  '21h30  Hugo — à payer',
  '21h45  Léa — payé [souhait 22h00]'
].join('\n');
await page.click('#importBtn');
await page.fill('#importText', pasted);
await page.click('#importApply');
console.log('--- COLLAGE TEXTE ---');
console.log('noms              ->', await page.$$eval('.card .name', e => e.map(x => x.textContent)));
console.log('paiements         ->', await page.$$eval('.meta button.chip', e => e.map(x => x.textContent)));
console.log('remis             ->', await page.$$eval('.card.is-done .name', e => e.map(x => x.textContent)));
console.log('souhaits/notes    ->', await page.$$eval('.chip-wish, .chip-note', e => e.map(x => x.textContent)));

// --- rubbish input is refused, queue untouched
await page.click('#importBtn');
await page.fill('#importText', 'bonjour, ceci n est pas une sauvegarde');
await page.click('#importApply');
console.log('entrée invalide   ->', await page.textContent('#importHint'));
console.log('fiche restée ouverte ->', await page.locator('#importScrim').isVisible(),
  '| lignes intactes', await page.$$eval('.card', e => e.length));
await page.click('#importCancel');

console.log('note stockage     ->', (await page.textContent('#storageNote')).replace(/\s+/g, ' ').trim());
const pips = await page.$$eval('.pip', e => [...new Set(e.map(x => {
  const r = x.getBoundingClientRect(); return Math.round(r.width) + 'x' + Math.round(r.height);
}))]);
console.log('pastilles         ->', pips, pips.every(v => v === '9x9') ? 'OK' : 'DEFORMEES');
console.log('overflow px       ->', await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth));

await page.screenshot({ path: '/tmp/shot-pwa-light.png', fullPage: true });
await page.emulateMedia({ colorScheme: 'dark' });
await page.screenshot({ path: '/tmp/shot-pwa-dark.png', fullPage: true });

console.log('erreurs           ->', errs.length ? errs : 'aucune');
await browser.close();
