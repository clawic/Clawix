import MarkdownIt from "markdown-it";
import hljs from "highlight.js/lib/core";
import javascript from "highlight.js/lib/languages/javascript";
import typescript from "highlight.js/lib/languages/typescript";
import bash from "highlight.js/lib/languages/bash";
import python from "highlight.js/lib/languages/python";
import json from "highlight.js/lib/languages/json";
import "highlight.js/styles/github-dark.css";

hljs.registerLanguage("javascript", javascript);
hljs.registerLanguage("typescript", typescript);
hljs.registerLanguage("bash", bash);
hljs.registerLanguage("python", python);
hljs.registerLanguage("json", json);

const md = new MarkdownIt({
  html: false,
  linkify: true,
  typographer: false,
  breaks: false,
  highlight: (code, lang) => {
    try {
      if (lang && hljs.getLanguage(lang)) {
        return `<pre class="hljs"><code>${hljs.highlight(code, { language: lang }).value}</code></pre>`;
      }
    } catch (_) {
      /* fall through */
    }
    return `<pre class="hljs"><code>${md.utils.escapeHtml(code)}</code></pre>`;
  }
});

const maxRenderableMarkdownBytes = 2 * 1024 * 1024;
const maxCachedEntries = 256;
const htmlCache = new Map<string, string>();

export function renderMarkdown(source: string): string {
  const safeSource = source ?? "";
  if (new TextEncoder().encode(safeSource).byteLength > maxRenderableMarkdownBytes) {
    return md.render(safeSource.slice(0, 8192));
  }
  return md.render(safeSource);
}

export function renderCachedMarkdown(source: string): string {
  const safeSource = source ?? "";
  const cached = htmlCache.get(safeSource);
  if (cached !== undefined) return cached;
  const html = renderMarkdown(safeSource);
  htmlCache.set(safeSource, html);
  if (htmlCache.size > maxCachedEntries) {
    const oldest = htmlCache.keys().next().value;
    if (oldest !== undefined) htmlCache.delete(oldest);
  }
  return html;
}
