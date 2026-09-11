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
 */
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const {execFileSync} = require('child_process');
const puppeteer = require('puppeteer-core');

const root = path.resolve(__dirname, '..');
const webDir = path.resolve(process.env.WEB_DIR || path.join(root, 'dist', 'web'));
const requiredLogs = [
  'S3TC support: enabled',
  'Loaded atlas texture: 16384x16384',
  'Loaded 6759 sprites from atlas',
  'All 80 enemies spawned (staggered)',
];
const forbiddenLogs = [
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

async function main() {
  if (!fs.existsSync(path.join(webDir, 'index.html'))) {
    throw new Error(`No web bundle at ${webDir}. Run npm run build:web first.`);
  }

  const server = makeServer();
  const failures = [];
  const logs = [];
  let browser;

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  try {
    const address = server.address();
    const url = `http://127.0.0.1:${address.port}/`;
    browser = await puppeteer.launch({
      executablePath: chromePath(),
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--enable-webgl', '--ignore-gpu-blocklist', '--enable-unsafe-swiftshader'],
    });
    const page = await browser.newPage();
    page.on('console', message => {
      const text = message.text();
      logs.push(text);
      console.log(`[browser:${message.type()}] ${text}`);
      if (message.type() === 'error') failures.push(`console error: ${text}`);
    });
    page.on('pageerror', error => failures.push(`page error: ${error.message}`));
    page.on('response', response => {
      if (response.status() >= 400) failures.push(`HTTP ${response.status()}: ${response.url()}`);
    });
    page.on('requestfailed', request => failures.push(`request failed: ${request.url()} (${request.failure()?.errorText || 'unknown error'})`));

    await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 30_000});
    await page.click('#canvas').catch(() => {}); // Mirrors the first real user gesture for audio startup.

    const deadline = Date.now() + 45_000;
    while (Date.now() < deadline && !requiredLogs.every(expected => logs.some(log => log.includes(expected)))) {
      await new Promise(resolve => setTimeout(resolve, 250));
    }

    for (const expected of requiredLogs) {
      if (!logs.some(log => log.includes(expected))) failures.push(`missing expected engine log: ${expected}`);
    }
    for (const forbidden of forbiddenLogs) {
      if (logs.some(log => log.includes(forbidden))) failures.push(`regression log: ${forbidden}`);
    }
    const title = await page.title();
    if (!/ents:\s*80\b/.test(title)) failures.push(`game did not reach the expected entity count (title: ${title})`);

    if (failures.length) throw new Error(`Web smoke test failed:\n- ${failures.join('\n- ')}`);
    console.log(`Web smoke test passed: ${title}`);
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
}

main().catch(error => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
