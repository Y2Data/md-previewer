/* ClearMark's offline rendering boundary. No document-supplied script is executed. */
(() => {
  'use strict';
  const article = document.getElementById('article');
  const send = (message) => window.webkit?.messageHandlers?.clearmark?.postMessage(message);
  let generation = 0;
  let renderQueue = Promise.resolve();
  const media = matchMedia('(prefers-color-scheme: dark)');
  let currentMarkdown = '', currentOptions = {};

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
      if (!safe || !src) { placeholder(image, 'Remote or unsupported image'); return; }
      image.src = safe;
      image.loading = 'lazy';
      image.decoding = 'async';
      image.addEventListener('error', () => placeholder(image, 'Image unavailable'), { once: true });
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
      const label = document.createElement('span'); label.className = 'callout-label'; label.textContent = match[1].toLowerCase();
      quote.prepend(label); quote.classList.add('callout-' + match[1].toLowerCase());
    });
    root.querySelectorAll('pre > code').forEach((code) => {
      const language = [...code.classList].find((c) => c.startsWith('language-'))?.slice(9) || 'text';
      if (language === 'mermaid') return;
      if (code.textContent.length <= 100_000 && window.hljs && hljs.getLanguage(language)) {
        code.innerHTML = hljs.highlight(code.textContent, { language, ignoreIllegals: true }).value;
      }
      const header = document.createElement('div'); header.className = 'code-header';
      const label = document.createElement('span'); label.textContent = language;
      const button = document.createElement('button'); button.className = 'copy-code'; button.type = 'button';
      button.textContent = 'Copy'; button.setAttribute('aria-label', 'Copy code');
      button.addEventListener('click', () => {
        send({ action: 'copy', text: code.textContent });
        if (!window.webkit) navigator.clipboard?.writeText(code.textContent).catch(() => {});
        button.textContent = 'Copied'; setTimeout(() => { button.textContent = 'Copy'; }, 1400);
      });
      header.append(label, button); code.parentElement.prepend(header);
    });
    return headings;
  }

  async function render(markdown, options = {}, ticket) {
    if (ticket !== generation) return;
    currentMarkdown = String(markdown); currentOptions = options;
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
    const headings = decorate(fragment);
    article.replaceChildren(fragment);
    send({ action: 'outline', items: headings });
    if (window.renderMathInElement) {
      renderMathInElement(article, {
        delimiters: [{ left: '$$', right: '$$', display: true }, { left: '\\[', right: '\\]', display: true }, { left: '\\(', right: '\\)', display: false }, { left: '$', right: '$', display: false }],
        throwOnError: false, strict: 'ignore', trust: false, maxExpand: 500, maxSize: 20,
        ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
      });
    }
    if (window.mermaid) {
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
          figure.setAttribute('aria-label', 'Mermaid diagram');
          figure.innerHTML = DOMPurify.sanitize(svg, { USE_PROFILES: { svg: true, svgFilters: true }, ADD_TAGS: ['style'], FORBID_TAGS: ['foreignObject', 'a'], FORBID_ATTR: ['href', 'xlink:href'] });
          pre.replaceWith(figure);
        } catch (_) {
          const note = document.createElement('span'); note.className = 'render-note';
          note.textContent = 'This diagram couldn’t be rendered. Its source is shown above.'; pre.append(note);
        }
      }
    }
    window.scrollTo(0, scrollY);
  }

  article.addEventListener('click', (event) => {
    const link = event.target.closest('a');
    if (!link) return;
    event.preventDefault();
    const href = link.getAttribute('href');
    if (!href) return;
    if (href.startsWith('#')) {
      try { document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' }); } catch (_) {}
    } else send({ action: 'link', href });
  });

  async function exportHTML() {
    await renderQueue;
    const clone = document.getElementById('reader').cloneNode(true);
    clone.querySelectorAll('.copy-code').forEach((node) => node.remove());
    for (const image of clone.querySelectorAll('img')) {
      const original = [...article.querySelectorAll('img')].find((item) => item.src === image.src);
      try {
        if (!original?.complete || !original.naturalWidth) throw new Error('unavailable');
        const scale = Math.min(1, 2400 / Math.max(original.naturalWidth, original.naturalHeight));
        const canvas = document.createElement('canvas'); canvas.width = Math.round(original.naturalWidth * scale); canvas.height = Math.round(original.naturalHeight * scale);
        canvas.getContext('2d').drawImage(original, 0, 0, canvas.width, canvas.height);
        image.src = canvas.toDataURL('image/png'); image.removeAttribute('loading');
      } catch (_) { placeholder(image, 'Image not included in export'); }
    }
    clone.querySelectorAll('a[href^="clearmark:"]').forEach((link) => link.removeAttribute('href'));
    // A script-free, portable document. MathML stays selectable and accessible without local fonts.
    clone.querySelectorAll('.katex').forEach((math) => {
      const mathml = math.querySelector('math');
      if (mathml) math.replaceWith(mathml.cloneNode(true));
    });
    const css = [...document.styleSheets].filter((sheet) => sheet.href?.endsWith('preview.css')).map((sheet) => [...sheet.cssRules].map((rule) => rule.cssText).join('\n')).join('\n');
    const title = document.createElement('span'); title.textContent = document.title;
    return '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'"><title>' + title.innerHTML + '</title><style>' + css + '</style></head><body>' + clone.outerHTML + '</body></html>';
  }

  window.ClearMark = {
    render(markdown, options = {}) {
      const ticket = ++generation;
      renderQueue = renderQueue.catch(() => {}).then(() => render(markdown, options, ticket));
      return renderQueue;
    },
    exportHTML,
  };
  media.addEventListener('change', () => { if (!currentOptions.theme || currentOptions.theme === 'system') window.ClearMark.render(currentMarkdown, currentOptions); });
})();
