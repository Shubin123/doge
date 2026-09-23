#!/usr/bin/env node
/*
 * Serve the freshly-built web bundle and assert that the real WebGL runtime
 * reaches gameplay. This deliberately runs against the output directory, not
 * source files: it catches missing wasm/data files, stale shell wiring, WebGL
 * extension regressions, shader link failures, and errors during atlas load.
 *
 * Usage:
 *   npm run build:web && npm run test:web:smoke
 *   npm run test:web
 *
 * CHROME_PATH=/path/to/chrome npm run test:web:smoke
 * WEB_URL=https://shubin123.github.io/doge/ npm run test:web:smoke   # test a deployed site
 * SMOKE_TIMEOUT_MS=120000 npm run test:web:smoke                     # slow (CI/software GL) hosts
 */
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const {execFileSync} = require('child_process');
const puppeteer = require('puppeteer-core');

const root = path.resolve(__dirname, '..');
const webDir = path.resolve(process.env.WEB_DIR || path.join(root, 'dist', 'web'));
const remoteUrl = process.env.WEB_URL;
const loadTimeoutMs = Number(process.env.SMOKE_TIMEOUT_MS) || 45_000;
// How long to keep playing after load before judging frames: "well into the
// game", not the first frame after the loading screen.
const playSeconds = Number(process.env.SMOKE_PLAY_SECONDS) || 15;
const minFps = Number(process.env.SMOKE_MIN_FPS) || 1;
const shotDir = path.resolve(process.env.SMOKE_SHOT_DIR || path.join(root, 'dist', 'e2e'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// Framebuffer gates. Frames are the composited canvas pixels (a screenshot),
// so they see exactly what a player sees, including post-processing.
const gates = {
  minLitFraction: 0.15,   // share of pixels brighter than near-black
  minColours: 48,         // distinct 4-bit-per-channel colours
  minLumaStd: 6,          // contrast; a flat fill or fog scores ~0
  minIdleDiff: 0.2,       // mean |Δluma| over 1s with no input (world animates)
  minMoveDiff: 1.0,       // mean |Δluma| after walking (camera/player moved)
};
const requiredLogs = [
  'S3TC support: enabled',
  'Loaded atlas texture: 16384x16384',
  'Loaded 6759 sprites from atlas',
  'All 80 enemies spawned (staggered)',
];
const forbiddenLogs = [
  '[engine alert]',
  'Cannot create image: DXT5 images are not supported on this system.',
  'Cannot link shader program object:',
  'precision mismatch between shaders',
];

function chromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  for (const command of ['google-chrome-stable', 'google-chrome', 'chromium', 'chromium-browser']) {
    try {
      return execFileSync('which', [command], {encoding: 'utf8'}).trim();
    } catch (_) {
      // Try the next common executable name.
    }
  }
  throw new Error('Chrome/Chromium was not found. Set CHROME_PATH to its executable.');
}

function contentType(file) {
  return ({
    '.css': 'text/css', '.data': 'application/octet-stream', '.html': 'text/html; charset=utf-8',
    '.ico': 'image/x-icon', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json',
    '.png': 'image/png', '.wasm': 'application/wasm', '.worker.js': 'text/javascript; charset=utf-8',
  })[path.extname(file)] || 'application/octet-stream';
}

function makeServer() {
  return http.createServer((request, response) => {
    const urlPath = decodeURIComponent((request.url || '/').split('?')[0]);
    const relative = urlPath === '/' ? 'index.html' : urlPath.replace(/^\/+/, '');
    const file = path.resolve(webDir, relative);
    if (!file.startsWith(`${webDir}${path.sep}`) || !fs.statSync(webDir).isDirectory()) {
      response.writeHead(400).end('Invalid path');
      return;
    }
    fs.stat(file, (error, stat) => {
      if (error || !stat.isFile()) {
        response.writeHead(404).end(`Not found: /${relative}`);
        return;
      }
      response.writeHead(200, {'Content-Type': contentType(file), 'Cache-Control': 'no-store'});
      fs.createReadStream(file).pipe(response);
    });
  });
}

// Screenshot the game canvas and reduce it to stats in the page itself (the
// browser already has a PNG decoder; no extra dependency).
async function captureFrame(page, name) {
  const canvas = await page.$('#canvas');
  const png = await canvas.screenshot({type: 'png'});
  fs.mkdirSync(shotDir, {recursive: true});
  fs.writeFileSync(path.join(shotDir, `${name}.png`), png);
  return page.evaluate(async b64 => {
    const img = new Image();
    img.src = `data:image/png;base64,${b64}`;
    await img.decode();
    const w = 200, h = Math.max(1, Math.round(200 * img.height / img.width));
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    const ctx = c.getContext('2d');
    ctx.drawImage(img, 0, 0, w, h);
    const px = ctx.getImageData(0, 0, w, h).data;
    const luma = new Array(w * h);
    const colours = new Set();
    let lit = 0, sum = 0, sumSq = 0;
    for (let i = 0, j = 0; i < px.length; i += 4, j++) {
      const y = 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      luma[j] = y; sum += y; sumSq += y * y;
      if (y > 12) lit++;
      colours.add((px[i] >> 4) << 8 | (px[i + 1] >> 4) << 4 | (px[i + 2] >> 4));
    }
    const n = luma.length, mean = sum / n;
    return {width: img.width, height: img.height, litFraction: lit / n, colours: colours.size,
            lumaMean: mean, lumaStd: Math.sqrt(Math.max(0, sumSq / n - mean * mean)), luma};
  }, png.toString('base64'));
}

async function canvasPoint(page, fx, fy) {
  const box = await (await page.$('#canvas')).boundingBox();
  return [box.x + box.width * fx, box.y + box.height * fy];
}

// Different GPU vendors expose different compressed-texture formats. Fake
// a GPU without S3TC, and one with a small texture limit, and require the
// shell to explain why it cannot run, without downloading the game data.
async function unsupportedGpuChecks(browser, url, failures) {
  const cases = [
    {name: 'no S3TC (e.g. mobile ETC2/ASTC-only GPU)', stub: 'noS3tc', expect: /S3TC/},
    {name: 'max texture 8192 (older iGPU)', stub: 'smallTex', expect: /Max texture size is 8192/},
  ];
  for (const c of cases) {
    const page = await browser.newPage();
    let dataRequested = false;
    page.on('request', request => { if (/game\.data|love\.wasm/.test(request.url())) dataRequested = true; });
    await page.evaluateOnNewDocument(stub => {
      const proto = WebGLRenderingContext.prototype;
      const getExtension = proto.getExtension, getParameter = proto.getParameter;
      proto.getExtension = function(name) {
        if (stub === 'noS3tc' && /compressed_texture_s3tc/i.test(name)) return null;
        return getExtension.call(this, name);
      };
      proto.getParameter = function(p) {
        if (stub === 'smallTex' && p === this.MAX_TEXTURE_SIZE) return 8192;
        return getParameter.call(this, p);
      };
    }, c.stub);
    await page.goto(url, {waitUntil: 'load', timeout: 60_000});
    await sleep(1000);
    const text = await page.$eval('#browserMessage', el => el.textContent);
    const status = await page.$eval('#engineStatus', el => el.textContent);
    console.log(`[caps] ${c.name}: ${status}`);
    if (status !== 'Unsupported GPU' || !c.expect.test(text)) failures.push(`unsupported GPU (${c.name}) not reported clearly: ${status} / ${text.slice(0, 120)}`);
    if (dataRequested) failures.push(`unsupported GPU (${c.name}) still downloaded the engine/game data`);
    await page.close();
  }
}

function frameDiff(a, b) {
  if (!a || !b || a.luma.length !== b.luma.length) return 0;
  let d = 0;
  for (let i = 0; i < a.luma.length; i++) d += Math.abs(a.luma[i] - b.luma[i]);
  return d / a.luma.length;
}

function describe(frame) {
  return `${frame.width}x${frame.height} lit=${frame.litFraction.toFixed(2)} colours=${frame.colours} ` +
         `luma=${frame.lumaMean.toFixed(1)}±${frame.lumaStd.toFixed(1)}`;
}

function checkFrame(frame, label, failures) {
  console.log(`[frame] ${label}: ${describe(frame)}`);
  if (frame.litFraction < gates.minLitFraction) failures.push(`${label}: frame is mostly black (lit=${frame.litFraction.toFixed(2)})`);
  if (frame.colours < gates.minColours) failures.push(`${label}: frame is near-uniform (${frame.colours} colours)`);
  if (frame.lumaStd < gates.minLumaStd) failures.push(`${label}: frame has no contrast (std=${frame.lumaStd.toFixed(1)})`);
}

async function main() {
  if (!remoteUrl && !fs.existsSync(path.join(webDir, 'index.html'))) {
    throw new Error(`No web bundle at ${webDir}. Run npm run build:web first.`);
  }

  const server = makeServer();
  const failures = [];
  const logs = [];
  let browser;

  if (!remoteUrl) {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
  }

  try {
    const url = remoteUrl || `http://127.0.0.1:${server.address().port}/`;
    browser = await puppeteer.launch({
      executablePath: chromePath(),
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--enable-webgl', '--ignore-gpu-blocklist', '--enable-unsafe-swiftshader'],
    });
    await unsupportedGpuChecks(browser, url, failures);

    const page = await browser.newPage();
    page.on('console', message => {
      const text = message.text();
      logs.push(text);
      console.log(`[browser:${message.type()}] ${text}`);
      if (message.type() === 'error') failures.push(`console error: ${text}`);
    });
    page.on('dialog', dialog => {
      failures.push(`browser dialog: ${dialog.message()}`);
      dialog.dismiss().catch(() => {});
    });
    page.on('pageerror', error => failures.push(`page error: ${error.message}`));
    page.on('response', response => {
      if (response.status() >= 400) failures.push(`HTTP ${response.status()}: ${response.url()}`);
    });
    page.on('requestfailed', request => failures.push(`request failed: ${request.url()} (${request.failure()?.errorText || 'unknown error'})`));

    await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 60_000});
    await page.click('#canvas').catch(() => {}); // Mirrors the first real user gesture for audio startup.

    const deadline = Date.now() + loadTimeoutMs;
    while (Date.now() < deadline && !requiredLogs.every(expected => logs.some(log => log.includes(expected)))) {
      await new Promise(resolve => setTimeout(resolve, 250));
    }

    for (const expected of requiredLogs) {
      if (!logs.some(log => log.includes(expected))) failures.push(`missing expected engine log: ${expected}`);
    }
    for (const forbidden of forbiddenLogs) {
      if (logs.some(log => log.includes(forbidden))) failures.push(`regression log: ${forbidden}`);
    }
    // The title is refreshed on a timer, so poll it rather than read once.
    const titleRe = /fps:\s*([\d.]+).*ents:\s*80\b/;
    let title = await page.title();
    for (const until = Date.now() + 15_000; Date.now() < until && !titleRe.test(title); await sleep(250)) {
      title = await page.title();
    }
    if (!titleRe.test(title)) failures.push(`game did not reach the expected entity count (title: ${title})`);

    // Compiling a shader is not enough: tracer and muzzle shaders are bound
    // only while firing. Keep firing while we play so this catches runtime
    // shader errors in the exact rendering path players use.
    await page.click('#canvas', {offset: {x: 600, y: 300}});
    for (let t = 0; t < playSeconds; t++) {
      await page.mouse.click(...(await canvasPoint(page, 0.5 + 0.3 * Math.cos(t), 0.5 + 0.3 * Math.sin(t))));
      await sleep(1000);
    }

    const played = await captureFrame(page, '1-played');
    checkFrame(played, `after ${playSeconds}s of play`, failures);

    await sleep(1000);
    const idle = await captureFrame(page, '2-idle');
    checkFrame(idle, 'idle +1s', failures);
    const idleDiff = frameDiff(played, idle);
    console.log(`[frame] idle diff: ${idleDiff.toFixed(2)}`);
    if (idleDiff < gates.minIdleDiff) failures.push(`frames are frozen: no change over 1s (diff=${idleDiff.toFixed(2)})`);

    // Walk for a bit: the player/camera must move, so the picture must change
    // well beyond ambient animation.
    await page.focus('#canvas');
    for (const key of ['KeyD', 'KeyS']) {
      await page.keyboard.down(key);
      await sleep(1200);
      await page.keyboard.up(key);
    }
    const moved = await captureFrame(page, '3-moved');
    checkFrame(moved, 'after walking', failures);
    const moveDiff = frameDiff(idle, moved);
    console.log(`[frame] move diff: ${moveDiff.toFixed(2)}`);
    if (moveDiff < gates.minMoveDiff) failures.push(`input had no visible effect (diff=${moveDiff.toFixed(2)})`);

    title = await page.title();
    const fps = Number((title.match(/fps:\s*([\d.]+)/) || [])[1] || 0);
    console.log(`[frame] fps after play: ${fps}`);
    if (fps < minFps) failures.push(`game loop stalled (fps ${fps} < ${minFps}; title: ${title})`);

    // Browser controls must stay outside the game canvas and forward their
    // state-changing input into LÖVE. Sound emits a Lua log, which verifies
    // that this is more than a cosmetic HTML toggle.
    const controlsPresent = await page.evaluate(() =>
      ['fullscreenButton', 'soundButton', 'lightsButton', 'menuButton', 'cacheButton']
        .every(id => document.getElementById(id))
    );
    if (!controlsPresent) {
      failures.push('browser control panel is incomplete');
    } else {
      await page.click('#soundButton');
      // Wait for the Lua side to log it: on software GL a frame can take seconds.
      for (const until = Date.now() + 20_000; Date.now() < until && !logs.some(log => log.includes('Audio muted')); await sleep(250)) {}
      const muted = await page.$eval('#soundButton', button => ({label: button.textContent, pressed: button.getAttribute('aria-pressed')}));
      if (muted.label !== 'Sound: Off' || muted.pressed !== 'false') failures.push('sound control did not enter its muted state');
      if (!logs.some(log => log.includes('Audio muted'))) failures.push('sound control did not reach the LÖVE audio mixer');

      await page.click('#soundButton');
      const unmuted = await page.$eval('#soundButton', button => ({label: button.textContent, pressed: button.getAttribute('aria-pressed')}));
      if (unmuted.label !== 'Sound: On' || unmuted.pressed !== 'true') failures.push('sound control did not restore its unmuted state');

      await page.click('#lightsButton');
      const lights = await page.$eval('#lightsButton', button => button.textContent);
      if (lights !== 'Lights: Off') failures.push('lights control did not update its state');
      await page.click('#lightsButton');
    }

    if (failures.length) throw new Error(`Web smoke test failed:\n- ${failures.join('\n- ')}`);
    console.log(`Web smoke test passed: ${title}`);
  } finally {
    await browser?.close();
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
}

main().catch(error => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
