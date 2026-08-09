import { chromium } from 'playwright';

// Serve this folder first:  python3 -m http.server 8899
// then:                      node test.mjs
const URL_ = 'http://localhost:8899/index.html';
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, locale: 'fr-FR' });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE ' + m.text()); });

// --- seed OLD-FORMAT data (no `wish` field), as already saved on the user's phone
await page.goto(URL_);
await page.evaluate(() => {
  localStorage.setItem('camembert-handover-v1', JSON.stringify({
    startTime: '21:30', perSlot: 2, slotMinutes: 15,
    lines: [
      { id: 'a1', name: 'Marie', note: '2 pièces', paid: true,  done: false },
      { id: 'a2', name: 'Luc',   note: '',         paid: false, done: true  },
      { id: 'a3', name: 'Anaïs', note: '',         paid: false, done: false },
      { id: 'a4', name: 'Thibault', note: '',      paid: true,  done: false },
      { id: 'a5', name: 'Zoé',   note: '',         paid: false, done: false }
    ]
  }));
});
await page.reload();

const names = () => page.$$eval('.card .name', e => e.map(x => x.textContent));
const clocks = () => page.$$eval('.clock', e => e.map(x => x.textContent));
console.log('MIGRATION old data ->', await names(), await clocks());
console.log('chips             ->', await page.$$eval('.meta .chip', e => e.map(x => x.textContent)));

// --- direct payment toggle on the card (no sheet)
const payChip = page.locator('.card').nth(2).locator('button.chip').first();
console.log('paiement avant    ->', await payChip.textContent(), await payChip.getAttribute('class'));
await payChip.click();
console.log('paiement après    ->', await page.locator('.card').nth(2).locator('button.chip').first().textContent());

// --- direct delivered toggle
await page.locator('.card').nth(2).locator('.check').click();
console.log('remis classes     ->', await page.$$eval('.card', e => e.map(x => x.className)));

// --- desired time: options generated from the configured start
await page.locator('.card').nth(4).locator('.name').click();
await page.waitForSelector('#scrim', { state: 'visible' });
const opts = await page.$$eval('#editWish option', e => e.map(x => x.textContent));
console.log('souhait options   ->', opts.slice(0, 6), '…', opts.length, 'total');
await page.selectOption('#editWish', '21:30');   // Zoé is 5th => real slot 22h00 => late by 30
console.log('hint              ->', await page.textContent('#wishHint'));
console.log('hint class        ->', await page.getAttribute('#wishHint', 'class'));
await page.click('#doneBtn');
await page.waitForSelector('#scrim', { state: 'hidden' });
console.log('souhait chip      ->', await page.$$eval('.chip-wish', e => e.map(x => x.textContent + ' [' + x.className + ']')));

// --- drag Zoé to the top: her wish is now met, chip must stop being late
const grip = page.locator('.card').nth(4).locator('.grip');
const top = page.locator('.card').nth(0);
const s = await grip.boundingBox(), d = await top.boundingBox();
await page.mouse.move(s.x + s.width / 2, s.y + s.height / 2);
await page.mouse.down();
for (let i = 1; i <= 12; i++) await page.mouse.move(s.x + s.width / 2, s.y + (d.y + 4 - s.y) * (i / 12), { steps: 2 });
await page.mouse.up();
console.log('après glissement  ->', await names());
console.log('souhait chip      ->', await page.$$eval('.chip-wish', e => e.map(x => x.textContent + ' [' + x.className + ']')));

// --- start time change re-times everything
await page.click('#cfgToggle');
await page.fill('#startTime', '22:00');
await page.dispatchEvent('#startTime', 'change');
console.log('base 22h00        ->', await clocks());
await page.fill('#startTime', '21:30');
await page.dispatchEvent('#startTime', 'change');

// --- SHARE: page is top-level here, so it must produce a link
await page.evaluate(() => navigator.clipboard.writeText('')); // ensure permission path
await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: 'http://localhost:8899' });
await page.click('#shareBtn');
await page.waitForFunction(() => document.getElementById('snackText').textContent.length > 0);
console.log('share snack       ->', await page.textContent('#snackText'));
const link = await page.evaluate(() => navigator.clipboard.readText());
console.log('lien longueur     ->', link.length, '| commence par', link.slice(0, 34));

// payment must not travel in the URL at all
const decoded = await page.evaluate(l => {
  const m = /#s=(.+)$/.exec(l);
  const pad = m[1].replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(pad + '='.repeat((4 - pad.length % 4) % 4));
  return new TextDecoder().decode(Uint8Array.from(bin, c => c.charCodeAt(0)));
}, link);
console.log('charge utile      ->', decoded);
console.log('FUITE paiement ?  ->', /paid|"p[ae]/.test(decoded) ? 'OUI' : 'non');

// --- open the snapshot as a PUBLIC reader in a clean context (no localStorage)
const pub = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'fr-FR' });
const rp = await pub.newPage();
rp.on('pageerror', e => errs.push('RO PAGEERROR ' + e.message));
await rp.goto(link);
console.log('--- VUE PUBLIQUE ---');
console.log('ordre             ->', await rp.$$eval('.card .name', e => e.map(x => x.textContent)));
console.log('heures            ->', await rp.$$eval('.clock', e => e.map(x => x.textContent)));
console.log('bandeau           ->', (await rp.textContent('#readonlyFlag')).replace(/\s+/g, ' ').trim());
console.log('chips visibles    ->', await rp.$$eval('.chip', e => e.map(x => x.textContent)));
console.log('poignées/ajout    ->', await rp.$$eval('.grip', e => e.length), await rp.$$eval('.vacant', e => e.length),
  await rp.locator('#composer').isVisible(), await rp.locator('#cfgToggle').isVisible());
console.log('texte rendu payer ->', (await rp.evaluate(() => document.body.innerText)).match(/payer|pay[ée]/gi) || 'absent');
console.log('DOM rendu (hors script) ->', (await rp.evaluate(() => {
  const c = document.body.cloneNode(true);
  c.querySelectorAll('script,style').forEach(e => e.remove());
  return c.textContent;
})).match(/payer|pay[ée]/gi) || 'absent');
await rp.locator('.card').nth(0).click();
console.log('clic -> fiche ?   ->', await rp.locator('#scrim').isVisible());
await rp.screenshot({ path: '/tmp/shot-public.png', fullPage: true });

// reader must not have written anything
console.log('storage lecteur   ->', await rp.evaluate(() => localStorage.getItem('camembert-handover-v1')));

// --- owner's data intact after all that
await page.reload();
console.log('--- PROPRIÉTAIRE ---');
console.log('ordre conservé    ->', await names());
console.log('paiements         ->', await page.$$eval('.meta button.chip', e => e.map(x => x.textContent)));
await page.screenshot({ path: '/tmp/shot-light.png', fullPage: true });
await page.emulateMedia({ colorScheme: 'dark' });
await page.screenshot({ path: '/tmp/shot-dark.png', fullPage: true });

// garde-fou : toute pastille doit rester un rond de 9px (collisions de classes)
const pipSizes = await page.$$eval('.pip', e => [...new Set(e.map(x => {
  const r = x.getBoundingClientRect(); return Math.round(r.width) + 'x' + Math.round(r.height);
}))]);
console.log('tailles pastilles ->', pipSizes, pipSizes.every(v => v === '9x9') ? 'OK' : 'DEFORMEES');
console.log('overflow px       ->', await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth));
console.log('erreurs           ->', errs.length ? errs : 'aucune');
await browser.close();
