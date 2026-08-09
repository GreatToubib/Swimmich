// Serve this folder first:  python3 -m http.server 8899
// then:                     node test.mjs
import { chromium } from 'playwright';

const URL_ = 'http://localhost:8899/index.html';
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, locale: 'fr-FR' });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE ' + m.text()); });

// --- seed data in the OLDEST stored format (no wish, no maxTotal), as saved by
// earlier versions: existing queues must survive an upgrade untouched.
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
console.log('MIGRATION ancien format ->', await names(), await clocks());
console.log('chips             ->', await page.$$eval('.meta .chip', e => e.map(x => x.textContent)));

// --- payment toggles straight from the line, no sheet
const payChip = page.locator('.card').nth(2).locator('button.chip').first();
console.log('paiement avant    ->', await payChip.textContent());
await payChip.click();
console.log('paiement après    ->', await page.locator('.card').nth(2).locator('button.chip').first().textContent());

// --- handover toggles straight from the line
await page.locator('.card').nth(2).locator('.check').click();
console.log('remis classes     ->', await page.$$eval('.card', e => e.map(x => x.className)));

// --- desired time, generated from the configured start
await page.locator('.card').nth(4).locator('.name').click();
await page.waitForSelector('#scrim', { state: 'visible' });
const opts = await page.$$eval('#editWish option', e => e.map(x => x.textContent));
console.log('souhait options   ->', opts.slice(0, 5), '…', opts.length, 'total');
await page.selectOption('#editWish', '21:30');   // Zoé sits 5th => 22h00 => 30 min late
console.log('hint              ->', await page.textContent('#wishHint'));
await page.click('#doneBtn');
await page.waitForSelector('#scrim', { state: 'hidden' });
console.log('souhait chip      ->', await page.$$eval('.chip-wish', e => e.map(x => x.textContent + ' [' + x.className + ']')));

// --- dragging Zoé to the top satisfies her wish: the late flag must clear
const grip = page.locator('.card').nth(4).locator('.grip');
const top = page.locator('.card').nth(0);
const s = await grip.boundingBox(), d = await top.boundingBox();
await page.mouse.move(s.x + s.width / 2, s.y + s.height / 2);
await page.mouse.down();
for (let i = 1; i <= 12; i++) await page.mouse.move(s.x + s.width / 2, s.y + (d.y + 4 - s.y) * (i / 12), { steps: 2 });
await page.mouse.up();
console.log('après glissement  ->', await names());
console.log('souhait chip      ->', await page.$$eval('.chip-wish', e => e.map(x => x.textContent + ' [' + x.className + ']')));

// --- the order survives a reload
await page.reload();
console.log('après rechargement->', await names());

// --- start time re-times the whole queue
await page.click('#cfgToggle');
await page.fill('#startTime', '22:00');
await page.dispatchEvent('#startTime', 'change');
console.log('base 22h00        ->', await clocks());
await page.fill('#startTime', '21:30');
await page.dispatchEvent('#startTime', 'change');
console.log('base 21h30        ->', await clocks());

// --- delete then undo
await page.locator('.card').nth(0).locator('.name').click();
await page.click('#deleteBtn');
console.log('après suppression ->', await names());
await page.click('#snackAction');
console.log('après annulation  ->', await names());

// --- pips stay round (guards the recurring class-collision bug)
const pips = await page.$$eval('.pip', e => [...new Set(e.map(x => {
  const r = x.getBoundingClientRect(); return Math.round(r.width) + 'x' + Math.round(r.height);
}))]);
console.log('pastilles         ->', pips, pips.every(v => v === '9x9') ? 'OK' : 'DEFORMEES');
console.log('overflow px       ->', await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth));

await page.screenshot({ path: '/tmp/shot-light.png', fullPage: true });
await page.emulateMedia({ colorScheme: 'dark' });
await page.screenshot({ path: '/tmp/shot-dark.png', fullPage: true });

console.log('erreurs           ->', errs.length ? errs : 'aucune');
await browser.close();
