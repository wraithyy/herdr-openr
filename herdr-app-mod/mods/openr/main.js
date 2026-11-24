// Openr for herdr-app: fuzzy-pick file paths and URLs mentioned in the focused
// terminal, newest first. Sources: its visible screen, or (Claude panes) the
// session transcript. Tab switches source. Enter opens (URL in the browser,
// file in EDITOR in a new tab), ctrl+f reveals in Finder / Explorer / the file manager,
// ctrl+y copies. macOS, Windows and Linux.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { slug, isAbsolute, extract } from "./paths.js";
import { exec, hc, home, readTextFile, run, theme, props, closeOverlay, focused, notify, window } from "herdr";

// {file} and {line} are replaced; argv, never a shell string, so text
// scraped from a terminal can't inject commands.
const EDITOR = ["nvim", "+{line}", "{file}"];
const TRANSCRIPT_LINES = 1000;
const VISIBLE = 14;

const platform = () => window()?.platform ?? "macos";
// PowerShell single-quoted literal: only quotes (curly ones too) need doubling, so text
// scraped from a terminal stays data.
const psQuote = (text) => `'${String(text).replace(/['\u2018\u2019\u201a\u201b]/g, "$&$&")}'`;
const ps = (script) => exec("powershell", ["-NoProfile", "-NonInteractive", "-Command", script]);
const dirname = (p) => p.replace(/[\\/][^\\/]*$/, "") || "/";

const openUrl = (url) => ({
  windows: () => exec("rundll32", ["url.dll,FileProtocolHandler", url]),
  linux: () => exec("xdg-open", [url]),
}[platform()] ?? (() => exec("open", [url])))();

const reveal = (path) => ({
  windows: () => exec("explorer", [`/select,${path.replace(/\//g, "\\")}`]),
  linux: () => exec("xdg-open", [dirname(path)]),
}[platform()] ?? (() => exec("open", ["-R", path])))();

const copyText = (text) => ({
  windows: () => ps(`Set-Clipboard -Value ${psQuote(text)}`),
  linux: () => exec("sh", ["-c", 'printf %s "$1" | (wl-copy 2>/dev/null || xclip -selection clipboard)', "sh", text]),
}[platform()] ?? (() => exec("sh", ["-c", 'printf %s "$1" | pbcopy', "sh", text])))();

// "d<path>" / "f<path>" per existing path, one process for all of them.
const existence = (paths) => (platform() === "windows"
  ? ps(`foreach ($p in @(${paths.map(psQuote).join(",") || "@()"})) { if (Test-Path -LiteralPath $p -PathType Container) { "d$p" } elseif (Test-Path -LiteralPath $p) { "f$p" } }`)
  : exec("sh", ["-c", 'for p; do if [ -d "$p" ]; then echo "d$p"; elif [ -e "$p" ]; then echo "f$p"; fi; done', "sh", ...paths]));


function matches(c, f) {
  const hay = c.label.toLowerCase();
  let i = 0;
  for (const ch of hay) if (ch === f[i]) i++;
  return i === f.length;
}

export default class Openr extends View {
  init(_props, cx) {
    const f = focused();
    this.terminal = f?.terminal ?? null;
    this.cwd = f?.cwd ?? home();
    this.mode = "visible";
    this.items = [];
    this.status = "reading…";
    this.filter = "";
    this.at = 0;
    this.input = InputState.new({ placeholder: "Open a file or URL from this terminal…" });
    this.input.on("change", (_e, cx) => {
      this.filter = this.input.value().toLowerCase();
      this.at = 0;
      cx.notify();
    });
    this.input.on("submit", () => this.open(this.rows()[this.at]));
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
    this.handle = cx.focus_handle();
    this.reload(cx);
  }

  reload(cx) {
    this.status = "reading…";
    this.items = [];
    cx.spawn(async (cx) => {
      try {
        const text = this.mode === "visible" ? await this.screen() : await this.transcript();
        this.items = text == null ? [] : await this.existing(extract(text));
        this.status = text == null ? "no Claude transcript for this terminal" : this.items.length ? "" : "nothing openable here";
      } catch (e) {
        this.status = `openr: ${e}`;
      }
      cx.notify();
    });
  }

  async screen() {
    if (!this.terminal) return "";
    const r = await hc(["read", this.terminal]);
    return r.stdout;
  }

  async transcript() {
    if (!this.terminal) return null;
    const r = await hc(["get", this.terminal, "--json"]);
    const fg = r.code === 0 ? JSON.parse(r.stdout).foreground : null;
    if (!fg?.pid) return null;
    const session = await readTextFile(`${home()}/.claude/sessions/${fg.pid}.json`);
    const sid = session && JSON.parse(session).sessionId;
    if (!sid) return null;
    const jsonl = await readTextFile(`${home()}/.claude/projects/${slug(fg.cwd)}/${sid}.jsonl`);
    if (!jsonl) return null;
    const out = [];
    for (const line of jsonl.split("\n").slice(-TRANSCRIPT_LINES)) {
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      for (const c of Array.isArray(msg?.message?.content) ? msg.message.content : []) {
        if (c.type === "tool_use") out.push(c.input?.file_path ?? c.input?.notebook_path ?? "");
        else if (c.type === "text") out.push(c.text);
      }
    }
    return out.join("\n");
  }

  // Keep URLs, and paths that exist relative to the terminal's folder. One sh for all checks.
  async existing(cands) {
    const resolve = (p) => {
      p = p.replace(/:[0-9]+$/, "").replace(/^~(?=\/|$)/, home());
      return isAbsolute(p) ? p : `${this.cwd}/${p}`;
    };
    const files = cands.filter((c) => c.kind === "file" && !c.label.startsWith("/dev/"));
    files.forEach((c) => (c.abs = resolve(c.label)));
    const r = files.length ? await existence(files.map((c) => c.abs)).catch(() => null) : null;
    const kind = new Map((r?.stdout ?? "").replace(/\r/g, "").split("\n").filter(Boolean).map((l) => [l.slice(1), l[0]]));
    const seen = new Set();
    return cands.filter((c) => {
      if (c.kind === "url") return true;
      if (!kind.has(c.abs) || seen.has(c.abs)) return false;
      seen.add(c.abs);
      if (kind.get(c.abs) === "d" && !c.label.endsWith("/")) c.label += "/";
      return true;
    });
  }

  rows() {
    return this.filter ? this.items.filter((c) => matches(c, this.filter)) : this.items;
  }

  close() {
    closeOverlay(props().overlay);
  }

  target(c) {
    return c.kind === "url" ? c.label : c.abs;
  }

  open(c) {
    if (!c) return;
    this.close();
    if (c.kind === "url") return openUrl(c.label);
    const argv = EDITOR.map((a) => a.replace("{file}", c.abs).replace("{line}", c.line));
    run("tab.new", { name: c.abs.split(/[\\/]/).pop(), folder: this.cwd, argv });
  }

  reveal(c) {
    if (!c) return;
    this.close();
    if (c.kind === "url") openUrl(c.label); else reveal(c.abs);
  }

  copy(c) {
    if (!c) return;
    this.close();
    copyText(this.target(c));
    notify({ title: "openr", body: `copied ${this.target(c)}`, timeout: 2500 });
  }

  render() {
    const t = theme();
    const rows = this.rows();
    this.at = Math.max(0, Math.min(this.at, rows.length - 1));
    const start = Math.max(0, this.at - VISIBLE + 1);
    const shown = rows.slice(start, start + VISIBLE);

    const row = (c, i) =>
      h_flex()
        .id(`or-${start + i}`)
        .mx(4)
        .px(10)
        .h(28)
        .rounded(7)
        .gap(10)
        .items_center()
        .cursor_pointer()
        .when(start + i === this.at, (el) => el.bg(t.hover))
        .hover((s) => s.bg(t.hover))
        .on_click(() => this.open(c))
        .child(div().w(30).flex_none().text_size(10.5).text_color(c.kind === "url" ? t.accent : t.dim).child(c.kind))
        .child(div().flex_1().truncate().text_color(t.foreground).child(c.label));

    const tab = (m, label) =>
      div().px(8).py(2).rounded(5).text_size(11).when(this.mode === m, (el) => el.bg(t.selected).text_color(t.foreground)).when(this.mode !== m, (el) => el.text_color(t.dim)).child(label);

    return v_flex()
      .id("openr")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(18)
      .gap(10)
      .bg(t.popover)
      .text_size(13)
      .on_key_down((e, cx) => {
        const k = e.key;
        const ctrl = e.modifiers.control;
        const sel = rows[this.at];
        if (k === "escape") return this.close();
        if (k === "down" || (ctrl && k === "n")) this.at = Math.min(this.at + 1, rows.length - 1);
        else if (k === "up" || (ctrl && k === "p")) this.at = Math.max(this.at - 1, 0);
        else if (k === "tab") {
          this.mode = this.mode === "visible" ? "transcript" : "visible";
          this.reload(cx);
        } else if (ctrl && k === "f") this.reveal(sel);
        else if (ctrl && k === "y") this.copy(sel);
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .child(
        h_flex()
          .items_center()
          .gap(4)
          .child(div().text_size(15).font_semibold().text_color(t.foreground).mr(8).child("Open"))
          .child(tab("visible", "screen"))
          .child(tab("transcript", "Claude transcript"))
          .child(div().flex_1())
          .child(div().text_size(11).text_color(t.dim).child("tab source · enter open · ctrl+f reveal · ctrl+y copy · esc")),
      )
      .child(
        h_flex().h(36).flex_none().px(10).items_center().rounded(9).border_1().border_color(t.accent).bg(t.background)
          .child(Input.new(this.input).flex_1().h_full().text_size(12.8).text_color(t.foreground)),
      )
      .child(
        v_flex()
          .min_h(0)
          .mb(6)
          .children(shown.length ? shown.map(row) : [div().px(14).py(10).text_color(t.dim).child(this.status || "No match")]),
      );
  }
}
