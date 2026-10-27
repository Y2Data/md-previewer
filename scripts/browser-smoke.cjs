const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const argument = (name) => process.argv.find((value) => value.startsWith(`--${name}=`))?.slice(name.length + 3);
const { chromium } = require(argument('playwright') || process.env.PLAYWRIGHT_PATH || 'playwright');

(async () => {
  const root = path.resolve(__dirname, '../ClearMark/Resources');
  const browser = await chromium.launch({
    ...((argument('chrome') || process.env.CHROME_PATH) ? { executablePath: argument('chrome') || process.env.CHROME_PATH } : {}),
    headless: true,
  });
  try {
    const context = await browser.newContext({ viewport: { width: 1060, height: 1000 }, deviceScaleFactor: 2, locale: 'en-US' });
    const page = await context.newPage();
    const unexpected = [], errors = [], messages = [], requested = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.exposeFunction('captureMessage', (message) => messages.push(message));
    await page.addInitScript(() => { window.webkit = { messageHandlers: { clearmark: { postMessage: (message) => window.captureMessage(message) } } }; });
    await page.route('**/*', async (route) => {
      const url = new URL(route.request().url());
      if (url.origin !== 'https://clearmark.test') { unexpected.push(url.href); return route.abort(); }
      requested.push(url.pathname);
      const file = path.resolve(root, '.' + decodeURIComponent(url.pathname));
      if (!file.startsWith(root + path.sep)) return route.abort();
      const type = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' }[path.extname(file)] || 'application/octet-stream';
      try { await route.fulfill({ body: await fs.readFile(file), contentType: type }); } catch { await route.fulfill({ status: 404, body: '' }); }
    });
    await page.goto('https://clearmark.test/preview.html');
    await page.waitForFunction(() => !!window.ClearMark);
    const render = (markdown, options = {}) => page.evaluate(({ markdown, options }) => window.ClearMark.render(markdown, options), { markdown, options });

    await render('# Plain Markdown\n\nFast by default.');
    assert.ok(!requested.some((p) => /mermaid|katex|auto-render|highlight/.test(p)), 'Plain Markdown loads no optional libraries');
    await render('# Disabled\n\n$x^2$\n\n```mermaid\ngraph LR\n A-->B\n```\n\n```swift\nlet x = 1\n```', { renderMath: false, renderDiagrams: false, highlightCode: false });
    assert.ok(!requested.some((p) => /mermaid|katex|auto-render|highlight/.test(p)), 'Disabled features never load their libraries');

    const welcome = await fs.readFile(path.join(root, 'Welcome.md'), 'utf8');
    await render(welcome, { title: 'Welcome to ClearMark', theme: 'light' });
    assert.equal(await page.locator('.mermaid-diagram svg').count(), 1, 'Mermaid renders offline');
    assert.equal(await page.locator('.katex').count(), 2, 'Inline and display math render');
    assert.ok(await page.locator('.hljs-keyword').count(), 'Swift is highlighted');
    assert.equal(await page.locator('input[type=checkbox]:disabled').count(), 5);
    assert.equal(await page.locator('.callout-tip').count(), 1);
    assert.ok(await page.locator('#outline a').count() >= 6);
    await page.getByRole('button', { name: 'Copy code' }).click();
    assert.ok(messages.some((m) => m.action === 'copy' && m.text.includes('struct AGoodTool')));
    await page.evaluate(() => window.scrollTo(0, 0));
    await fs.mkdir(path.resolve(__dirname, '../docs'), { recursive: true });
    await page.screenshot({ path: path.resolve(__dirname, '../docs/reader-light.png') });
    await render(welcome, { title: 'Welcome to ClearMark', theme: 'dark' });
    await page.screenshot({ path: path.resolve(__dirname, '../docs/reader-dark.png') });

    await render(welcome, { language: 'zh-Hans', theme: 'paper', showOutline: true });
    assert.equal(await page.locator('html').getAttribute('lang'), 'zh-Hans');
    assert.equal(await page.getByRole('button', { name: '复制代码' }).count(), 1);
    assert.equal(await page.locator('#outline summary').innerText(), '文档目录');
    assert.equal(await page.locator('#local-caption').innerText(), '本地预览');
    await page.screenshot({ path: path.resolve(__dirname, '../docs/preview-chinese.png') });
    await render('# One\n\n## Two', { showOutline: false });
    assert.equal(await page.locator('#outline').isVisible(), false);

    await render('# Same\n\n## Same\n\n## Same-1\n\n## 日本語の見出し\n\n[Jump](#same-1)');
    const ids = await page.locator('h1,h2').evaluateAll((nodes) => nodes.map((n) => n.id));
    assert.equal(new Set(ids).size, ids.length, 'Heading IDs are unique, including slug collisions');
    assert.ok(ids.some((id) => id.includes('日本語')));

    await render(`# Safe
<script>window.compromised = true</script>
<img src="https://tracker.invalid/pixel" onerror="window.compromised=true">
<img src="//tracker.invalid/other">
<img src="data:text/html,<script>alert(1)</script>">
<iframe src="https://tracker.invalid/frame"></iframe>
<form action="https://tracker.invalid/post"><input autofocus><button>Send</button></form>
<style>body { display: none }</style>
<svg onload="window.compromised=true"><script>window.compromised=true</script></svg>
[bad](javascript:alert(1))
<a href="file:///etc/passwd">file</a>
<div id="article" name="ClearMark" style="background:url(https://tracker.invalid/css)">Text</div>`);
    assert.equal(await page.locator('#article script,#article iframe,#article form,#article style,#article button,#article [onerror],#article [onload],#article [style]').count(), 0);
    assert.equal(await page.evaluate(() => !!window.compromised), false);
    assert.equal(await page.locator('#article a[href]').count(), 0);
    assert.equal(await page.locator('#article').count(), 1, 'Document cannot clobber renderer IDs');
    assert.equal(unexpected.length, 0, 'No external requests, including images');

    await render('# Resilient\n\n```mermaid\nnot a valid diagram !!!\n```\n\nStill readable.');
    assert.equal(await page.locator('.render-note').count(), 1);
    assert.ok((await page.locator('#article').innerText()).includes('Still readable.'));

    await page.evaluate(async () => {
      await Promise.all([window.ClearMark.render('# Old\n```mermaid\ngraph LR\n A-->B\n```'), window.ClearMark.render('# Latest')]);
    });
    assert.equal(await page.locator('h1').innerText(), 'Latest', 'Latest update wins');

    assert.equal(errors.length, 0, errors.join('\n'));
    console.log('PASS: Markdown, math, diagrams, highlighting, outline IDs, copy, themes, malicious HTML, network isolation, malformed diagrams, render races, localization, and on-demand assets.');
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
