// bun test herdr-app-mod/mods/openr
import { expect, test } from "bun:test";
import { extract, slug, isAbsolute } from "./paths.js";

test("transcript folder: every non-alphanumeric becomes -", () => {
  expect(slug("/Users/me/.local/share/chezmoi")).toBe("-Users-me--local-share-chezmoi");
  expect(slug("/var/folders/bf/x_5_y")).toBe("-var-folders-bf-x-5-y");
  expect(slug("C:\\Users\\me\\proj")).toBe("C--Users-me-proj");
});

test("paths: unix, relative, Windows drive, with line numbers", () => {
  const labels = extract("edit src/a.ts:12 and C:\\work\\app\\main.rs:3 then /etc/hosts or C:/x/y.md").map((c) => c.label);
  expect(labels).toEqual(["C:/x/y.md", "/etc/hosts", "C:\\work\\app\\main.rs:3", "src/a.ts:12"]);
  expect(extract("C:\\a\\b.ts:7")[0].line).toBe("7");
});

test("absolute paths on both platforms", () => {
  expect(isAbsolute("/x")).toBe(true);
  expect(isAbsolute("C:\\x")).toBe(true);
  expect(isAbsolute("D:/x")).toBe(true);
  expect(isAbsolute("src/x")).toBe(false);
});
