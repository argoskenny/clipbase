import { describe, expect, test } from "vitest";
import { applyTheme, getInitialTheme, THEME_STORAGE_KEY } from "../src/theme";

class MemoryStorage {
  private values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

describe("theme preferences", () => {
  test("uses persisted dark theme before system preference", () => {
    const storage = new MemoryStorage();
    storage.setItem(THEME_STORAGE_KEY, "dark");

    expect(getInitialTheme(storage, () => false)).toBe("dark");
  });

  test("falls back to system dark preference", () => {
    expect(getInitialTheme(new MemoryStorage(), () => true)).toBe("dark");
  });

  test("applies and persists theme on the document root", () => {
    const storage = new MemoryStorage();
    const root = { dataset: {} as Record<string, string> };

    applyTheme("dark", root, storage);

    expect(root.dataset.theme).toBe("dark");
    expect(storage.getItem(THEME_STORAGE_KEY)).toBe("dark");
  });
});
