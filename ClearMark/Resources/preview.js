/* ClearMark's offline rendering boundary. No document-supplied script is executed. */
(() => {
  'use strict';
  const article = document.getElementById('article');
  const send = (message) => window.webkit?.messageHandlers?.clearmark?.postMessage(message);
  let generation = 0;
  let renderQueue = Promise.resolve();
  const media = matchMedia('(prefers-color-scheme: dark)');
  let currentMarkdown = '', currentOptions = {};
  const translations = {
    en: { copy: 'Copy', copied: 'Copied', copyCode: 'Copy code', outline: 'On this page', local: 'LOCAL PREVIEW', preview: 'Markdown preview', footer: 'Made readable with ClearMark.', remoteImage: 'Remote or unsupported image', unavailableImage: 'Image unavailable', diagram: 'Mermaid diagram', diagramError: 'This diagram couldn’t be rendered. Its source is shown above.', note: 'Note', tip: 'Tip', important: 'Important', warning: 'Warning', caution: 'Caution' },
    zh: { copy: '复制', copied: '已复制', copyCode: '复制代码', outline: '文档目录', local: '本地预览', preview: 'Markdown 预览', footer: '由 ClearMark 清晰呈现。', remoteImage: '远程图片或不支持的格式', unavailableImage: '无法加载图片', diagram: 'Mermaid 图表', diagramError: '无法渲染此图表，已保留上方源码。', note: '备注', tip: '提示', important: '重要', warning: '警告', caution: '注意' },
  };
  const t = (key) => translations[(currentOptions.language || navigator.language).startsWith('zh') ? 'zh' : 'en'][key];
  const assets = new Map();
  function loadAsset(path, stylesheet = false) {
    if (assets.has(path)) return assets.get(path);
    const pending = new Promise((resolve, reject) => {
      const element = document.createElement(stylesheet ? 'link' : 'script');
      const timeout = setTimeout(() => { element.remove(); assets.delete(path); reject(new Error('Asset load timed out')); }, 8000);
      element.onload = () => { clearTimeout(timeout); resolve(); };
      element.onerror = () => { clearTimeout(timeout); element.remove(); assets.delete(path); reject(new Error('Asset unavailable')); };
      if (stylesheet) { element.rel = 'stylesheet'; element.href = path; }
      else element.src = path;
      document.head.append(element);
    });
    assets.set(path, pending);
    return pending;
  }

  function updateOutline(headings, enabled) {
    const outline = document.getElementById('outline');
    outline.replaceChildren();
    outline.hidden = !enabled || headings.length < 2;
    outline.setAttribute('aria-label', t('outline'));
    if (outline.hidden) return;
    const details = document.createElement('details');
    const summary = document.createElement('summary'); summary.textContent = t('outline');
    const list = document.createElement('ul');
    for (const heading of headings.slice(0, 200)) {
      const item = document.createElement('li'), link = document.createElement('a');
      link.href = '#' + encodeURIComponent(heading.id); link.textContent = heading.title;
      item.style.marginLeft = `${Math.max(0, heading.level - 2) * 12}px`;
      item.append(link); list.append(item);
    }
    details.append(summary, list); outline.append(details);
  }

  function safeURL(value, image = false) {
    try {
      if (image && /^data:image\/(png|jpeg|gif|webp|avif);base64,[a-z\d+/=\s]+$/i.test(value) && value.length < 2_800_000) return value;
      const url = new URL(value, 'clearmark://document/');
      if (url.protocol === 'clearmark:' && url.hostname === 'document') {
        // Same-origin image resources can be embedded into a portable HTML export.
        return image ? 'clearmark://bundle/_images' + url.pathname : url.href;
      }
      if (!image && ['https:', 'http:', 'mailto:'].includes(url.protocol)) return url.href;
    } catch (_) { /* Malformed URLs become inert. */ }
    return null;
  }

  function placeholder(image, reason) {
    const span = document.createElement('span');
    span.className = 'image-placeholder';
    span.textContent = `${reason}${image.alt ? ' · ' + image.alt : ''}`;
    image.replaceWith(span);
  }

  function decorate(root) {
    const used = new Map();
    const headings = [];
    root.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach((heading) => {
      const title = heading.textContent.trim();
      const base = title.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').trim().replace(/\s+/g, '-') || 'section';
      let count = used.get(base) || 0;
      let id = base + (count ? '-' + count : '');
      while (root.querySelector(`[id="${CSS.escape(id)}"]`)) { count++; id = base + '-' + count; }
      used.set(base, count + 1);
      heading.id = id;
      headings.push({ id, title, level: Number(heading.tagName[1]) });
    });
    root.querySelectorAll('a').forEach((link) => {
      const href = link.getAttribute('href') || '';
      if (!href) { link.removeAttribute('href'); return; }
      if (href.startsWith('#')) return;
      const safe = safeURL(href);
      if (safe) { link.href = safe; link.rel = 'noreferrer noopener'; }
      else link.removeAttribute('href');
      link.removeAttribute('target');
    });
    root.querySelectorAll('img').forEach((image) => {
      const src = image.getAttribute('src') || '';
      const safe = safeURL(src, true);
      if (!safe || !src) { placeholder(image, t('remoteImage')); return; }
      image.src = safe;
      image.loading = 'lazy';
      image.decoding = 'async';
      image.addEventListener('error', () => placeholder(image, t('unavailableImage')), { once: true });
    });
    root.querySelectorAll('input').forEach((input) => {
      if (input.type === 'checkbox') input.disabled = true;
      else input.remove();
    });
    root.querySelectorAll('table').forEach((table) => {
      const container = document.createElement('div'); container.className = 'table-scroll';
      table.replaceWith(container); container.append(table);
    });
    root.querySelectorAll('blockquote').forEach((quote) => {
      const first = quote.querySelector('p');
      if (!first) return;
      const match = first.textContent.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i);
      if (!match) return;
      const walker = document.createTreeWalker(first, NodeFilter.SHOW_TEXT);
      let remaining = match[0].length;
      while (remaining > 0 && walker.nextNode()) {
        const node = walker.currentNode, take = Math.min(remaining, node.textContent.length);
        node.textContent = node.textContent.slice(take); remaining -= take;
      }
      const label = document.createElement('span'); label.className = 'callout-label'; label.textContent = t(match[1].toLowerCase());
      quote.prepend(label); quote.classList.add('callout-' + match[1].toLowerCase());
    });
    root.querySelectorAll('pre > code').forEach((code) => {
      const language = [...code.classList].find((c) => c.startsWith('language-'))?.slice(9) || 'text';
      if (language === 'mermaid' && currentOptions.renderDiagrams !== false) return;
      if (currentOptions.highlightCode !== false && code.textContent.length <= 100_000 && window.hljs && hljs.getLanguage(language)) {
        code.innerHTML = hljs.highlight(code.textContent, { language, ignoreIllegals: true }).value;
      }
      const header = document.createElement('div'); header.className = 'code-header';
      const label = document.createElement('span'); label.textContent = language;
      const button = document.createElement('button'); button.className = 'copy-code'; button.type = 'button';
      button.textContent = t('copy'); button.setAttribute('aria-label', t('copyCode'));
      button.addEventListener('click', () => {
        send({ action: 'copy', text: code.textContent });
        if (!window.webkit) navigator.clipboard?.writeText(code.textContent).catch(() => {});
        button.textContent = t('copied'); setTimeout(() => { button.textContent = t('copy'); }, 1400);
      });
      header.append(label, button); code.parentElement.prepend(header);
    });
    return headings;
  }

  async function render(markdown, options = {}, ticket) {
    if (ticket !== generation) return;
    currentMarkdown = String(markdown); currentOptions = options;
    document.documentElement.lang = (options.language || navigator.language).startsWith('zh') ? 'zh-Hans' : 'en';
    document.getElementById('local-caption').textContent = t('local');
    document.getElementById('footer-caption').textContent = t('footer');
    article.setAttribute('aria-label', t('preview'));
    const dark = options.theme === 'dark' || ((!options.theme || options.theme === 'system') && media.matches);
    document.documentElement.dataset.theme = options.theme || 'system';
    document.documentElement.style.setProperty('--font-size', `${Math.min(24, Math.max(13, Number(options.fontSize) || 17))}px`);
    document.documentElement.style.setProperty('--content-width', options.wide ? '1100px' : '760px');
    document.title = options.title || 'ClearMark';
    document.getElementById('document-name').textContent = options.title || 'Markdown';
    const scrollY = window.scrollY;
    // Display YAML front matter as metadata only; never interpret it as configuration.
    const source = currentMarkdown.replace(/^\uFEFF/, '').replace(/^---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)\r?\n/, '');
    const raw = marked.parse(source, { gfm: true, breaks: false });
    const fragment = DOMPurify.sanitize(raw, {
      RETURN_DOM_FRAGMENT: true, USE_PROFILES: { html: true },
      FORBID_TAGS: ['style', 'script', 'iframe', 'object', 'embed', 'form', 'textarea', 'select', 'button', 'link', 'meta', 'base', 'audio', 'video', 'source'],
      FORBID_ATTR: ['style', 'srcset', 'id', 'name', 'ping', 'form', 'autofocus', 'contenteditable'],
      ALLOW_DATA_ATTR: false,
    });
    const needsCode = options.highlightCode !== false && !!fragment.querySelector('pre > code:not(.language-mermaid)');
    const needsDiagrams = options.renderDiagrams !== false && !!fragment.querySelector('pre > code.language-mermaid');
    const mathProbe = fragment.cloneNode(true);
    mathProbe.querySelectorAll('pre,code').forEach((node) => node.remove());
    const needsMath = options.renderMath !== false && /(\$\$[\s\S]+?\$\$|\$[^$\n]+?\$|\\\([\s\S]+?\\\)|\\\[[\s\S]+?\\\])/.test(mathProbe.textContent);
    await Promise.all([
      needsCode ? loadAsset('Vendor/highlight.min.js') : null,
      needsDiagrams ? loadAsset('Vendor/mermaid.min.js') : null,
      needsMath ? Promise.all([loadAsset('Vendor/katex.min.css', true), loadAsset('Vendor/katex.min.js')]).then(() => loadAsset('Vendor/auto-render.min.js')) : null,
    ]);
    if (ticket !== generation) return;
    const headings = decorate(fragment);
    article.replaceChildren(fragment);
    updateOutline(headings, options.showOutline !== false);
    if (needsMath && window.renderMathInElement) {
      renderMathInElement(article, {
        delimiters: [{ left: '$$', right: '$$', display: true }, { left: '\\[', right: '\\]', display: true }, { left: '\\(', right: '\\)', display: false }, { left: '$', right: '$', display: false }],
        throwOnError: false, strict: 'ignore', trust: false, maxExpand: 500, maxSize: 20,
        ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
      });
    }
    if (needsDiagrams && window.mermaid) {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'base', suppressErrorRendering: true, maxTextSize: 12000, maxEdges: 300,
        flowchart: { htmlLabels: false, useMaxWidth: true },
        themeVariables: dark ? {} : { primaryColor: '#edf5ef', primaryTextColor: '#305541', primaryBorderColor: '#9ab7a4', lineColor: '#87a694', secondaryColor: '#f8f5ed', tertiaryColor: '#f4f7f3', fontFamily: '-apple-system, sans-serif', fontSize: '14px' },
      });
      let index = 0;
      for (const code of article.querySelectorAll('pre > code.language-mermaid')) {
        if (ticket !== generation) return;
        const pre = code.parentElement;
        try {
          if (index >= 12 || code.textContent.length > 12000) throw new Error('limit');
          const { svg } = await mermaid.render(`diagram-${ticket}-${index++}`, code.textContent);
          if (ticket !== generation) return;
          const figure = document.createElement('figure'); figure.className = 'mermaid-diagram';
          figure.setAttribute('aria-label', t('diagram'));
          figure.innerHTML = DOMPurify.sanitize(svg, { USE_PROFILES: { svg: true, svgFilters: true }, ADD_TAGS: ['style'], FORBID_TAGS: ['foreignObject', 'a'], FORBID_ATTR: ['href', 'xlink:href'] });
          pre.replaceWith(figure);
        } catch (_) {
          const note = document.createElement('span'); note.className = 'render-note';
          note.textContent = t('diagramError'); pre.append(note);
        }
      }
    }
    window.scrollTo(0, scrollY);
  }

  document.getElementById('reader').addEventListener('click', (event) => {
    const link = event.target.closest('a');
    if (!link) return;
    event.preventDefault();
    const href = link.getAttribute('href');
    if (!href) return;
    if (href.startsWith('#')) {
      try { document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' }); } catch (_) {}
    } else send({ action: 'link', href });
  });

  window.ClearMark = {
    render(markdown, options = {}) {
      const ticket = ++generation;
      renderQueue = renderQueue.catch(() => {}).then(() => render(markdown, options, ticket));
      return renderQueue;
    },
  };
  media.addEventListener('change', () => { if (!currentOptions.theme || currentOptions.theme === 'system') window.ClearMark.render(currentMarkdown, currentOptions); });
})();
