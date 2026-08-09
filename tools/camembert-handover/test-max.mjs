import { chromium } from 'playwright';

// Serve this folder first:  python3 -m http.server 8899
// then:                     node test-max.mjs

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, locale: 'fr-FR' });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
page.on('console', m => { if (m.type() === 'error' && !/favicon|404/.test(m.text())) errs.push('CONSOLE ' + m.text()); });
await page.goto('http://localhost:8899/index.html');

const add = async n => { await page.fill('#newName', n); await page.click('.composer button[type=submit]'); };
const count = () => page.$$eval('.card', e => e.length);
const snackVisible = () => page.locator('#snack').isVisible();

// --- pas de plafond par défaut : le champ est vide
await page.click('#cfgToggle');
console.log('champ max défaut  ->', JSON.stringify(await page.inputValue('#maxTotal')));

// --- régler un plafond de 3
await page.fill('#maxTotal', '3');
await page.dispatchEvent('#maxTotal', 'change');
for (const n of ['Marie', 'Luc']) await add(n);
console.log('2 lignes, compteur->', await page.textContent('#tallyLines'), '| classe', await page.$eval('#tallyLines', e => e.parentElement.className));
console.log('places libres     ->', await page.$$eval('.vacant', e => e.length), '(1 attendue : 1 restante)');

await add('Anaïs');
console.log('3 lignes, compteur->', await page.textContent('#tallyLines'), '| classe', await page.$eval('#tallyLines', e => e.parentElement.className));
console.log('places libres     ->', await page.$$eval('.vacant', e => e.length), '(0 attendue : plafond atteint)');
console.log('placeholder       ->', await page.getAttribute('#newName', 'placeholder'));

// --- LA 4e DOIT ÊTRE REFUSÉE
await page.fill('#newName', 'Thibault');
await page.click('.composer button[type=submit]');
await page.waitForFunction(() => document.getElementById('snackText').textContent.includes('Maximum'));
console.log('--- REFUS ---');
console.log('message           ->', await page.textContent('#snackText'));
console.log('snack en erreur   ->', await page.getAttribute('#snack', 'class'), '| role', await page.getAttribute('#snack', 'role'));
console.log('lignes            ->', await count(), '(3 attendues : rien ajouté)');
console.log('nom conservé      ->', JSON.stringify(await page.inputValue('#newName')));
console.log('champ signalé     ->', await page.getAttribute('#newName', 'class'), await page.getAttribute('#newName', 'aria-invalid'));

// --- le raccourci du message ouvre les réglages sur le champ
await page.click('#cfgToggle');                       // referme
console.log('réglages fermés   ->', await page.locator('#cfg').isVisible());
await page.click('#snackAction');
console.log('après raccourci   ->', 'réglages', await page.locator('#cfg').isVisible(),
  '| focus', await page.evaluate(() => document.activeElement.id));

// --- relever le plafond débloque l'ajout, le nom saisi est toujours là
await page.fill('#maxTotal', '5');
await page.dispatchEvent('#maxTotal', 'change');
await page.click('.composer button[type=submit]');
console.log('après relèvement  ->', await count(), 'lignes |', await page.$$eval('.card .name', e => e.map(x => x.textContent)));

// --- abaisser sous le nombre de lignes ne supprime rien
await page.fill('#maxTotal', '2');
await page.dispatchEvent('#maxTotal', 'change');
await page.waitForFunction(() => document.getElementById('snackText').textContent.includes('Maximum à'));
console.log('--- ABAISSEMENT ---');
console.log('message           ->', await page.textContent('#snackText'));
console.log('lignes intactes   ->', await count(), '(4 attendues)');
console.log('compteur          ->', await page.textContent('#tallyLines'));

// --- remettre 0 = illimité
await page.fill('#maxTotal', '0');
await page.dispatchEvent('#maxTotal', 'change');
console.log('--- ILLIMITÉ ---');
console.log('champ vidé        ->', JSON.stringify(await page.inputValue('#maxTotal')));
console.log('compteur          ->', await page.textContent('#tallyLines'), '| classe', await page.$eval('#tallyLines', e => e.parentElement.className));
await add('Zoé');
console.log('ajout permis      ->', await count(), 'lignes | placeholder', await page.getAttribute('#newName', 'placeholder'));

// --- le plafond survit au rechargement
await page.fill('#maxTotal', '6');
await page.dispatchEvent('#maxTotal', 'change');
await page.reload();
await page.click('#cfgToggle');
console.log('après rechargement->', 'max =', JSON.stringify(await page.inputValue('#maxTotal')), '| compteur', await page.textContent('#tallyLines'));

// --- pastilles toujours rondes
const pips = await page.$$eval('.pip', e => [...new Set(e.map(x => {
  const r = x.getBoundingClientRect(); return Math.round(r.width) + 'x' + Math.round(r.height);
}))]);
console.log('pastilles         ->', pips, pips.every(v => v === '9x9') ? 'OK' : 'DEFORMEES');

await page.fill('#maxTotal', '6');
await page.dispatchEvent('#maxTotal', 'change');
await add('Camille');
await page.fill('#newName', 'Refusé');
await page.click('.composer button[type=submit]');
await page.screenshot({ path: '/tmp/shot-max-light.png', fullPage: true });
await page.emulateMedia({ colorScheme: 'dark' });
await page.screenshot({ path: '/tmp/shot-max-dark.png', fullPage: true });

console.log('overflow px       ->', await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth));
console.log('erreurs           ->', errs.length ? errs : 'aucune');
await browser.close();
