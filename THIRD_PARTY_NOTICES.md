# Third-party software

ClearMark bundles these libraries so documents render without network access. Their licenses are included in `ClearMark/Resources/Vendor/Licenses`.

| Library | Version | License | Use |
| --- | --- | --- | --- |
| [Marked](https://github.com/markedjs/marked) | 18.1.2 | MIT | Markdown parser |
| [DOMPurify](https://github.com/cure53/DOMPurify) | 3.4.17 | Apache-2.0 OR MPL-2.0 | HTML and SVG sanitization |
| [Highlight.js](https://github.com/highlightjs/highlight.js) | 11.12.0 | BSD-3-Clause | Syntax highlighting |
| [KaTeX](https://github.com/KaTeX/KaTeX) | 0.19.1 | MIT | Math layout and bundled fonts |
| [Mermaid](https://github.com/mermaid-js/mermaid) | 12.2.0 | MIT | Diagrams |

`Vendor/manifest.json` records the upstream npm package URLs, their published integrity hashes, and SHA-256 hashes for every checked-in asset. Highlight.js’s browser build comes from `https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.12.0/highlight.min.js`; its license matches the main package.

Development-only browser checks use Playwright (Apache-2.0). It is not shipped inside ClearMark.
