// Pure helpers (no herdr import), so bun can test them.

export const MAX_CANDIDATES = 300;

export const URL_RE = /https?:\/\/[^\s"'`$()\]>]+/g;
// Unix paths, relative paths with a slash, bare file names, and Windows drive paths (C:\x\y.ts, C:/x).
export const PATH_RE = /([A-Za-z]:[\\/][A-Za-z0-9_.@~\\/-]+|\/[A-Za-z0-9_.@~-][A-Za-z0-9_.@~\/-]*|[A-Za-z0-9_.@~-]+[\\/][A-Za-z0-9_.@~\\/-]+|[A-Za-z0-9_@~][A-Za-z0-9_.@~\\/-]*\.[A-Za-z0-9]+)(:[0-9]+)?/g;

// Claude Code stores its transcript under the project folder with every character but
// letters and digits turned into - ("/a/b_c" -> "-a-b-c", "C:\\x" -> "C--x").
export const slug = (cwd) => cwd.replace(/[^A-Za-z0-9]/g, "-");

export const isAbsolute = (p) => p.startsWith("/") || /^[A-Za-z]:[\\/]/.test(p);

export function extract(text) {
  const found = [];
  for (const line of text.split("\n")) {
    for (const m of line.matchAll(URL_RE)) found.push({ kind: "url", label: m[0] });
    for (const m of line.replace(URL_RE, " ").matchAll(PATH_RE)) found.push({ kind: "file", label: m[0], line: m[2] ? m[2].slice(1) : "1" });
  }
  const seen = new Set();
  return found.reverse().filter((c) => !seen.has(c.label) && seen.add(c.label)).slice(0, MAX_CANDIDATES);
}
