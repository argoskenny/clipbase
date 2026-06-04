export type ThemeMode = "light" | "dark";

export const THEME_STORAGE_KEY = "clipbase-theme";

type ThemeStorage = {
  getItem: (key: string) => string | null;
  setItem: (key: string, value: string) => void;
};

type ThemeRoot = {
  dataset: {
    theme?: string;
  };
};

function isThemeMode(value: string | null): value is ThemeMode {
  return value === "light" || value === "dark";
}

export function getInitialTheme(storage: ThemeStorage | null | undefined, prefersDark: () => boolean): ThemeMode {
  try {
    const persistedTheme = storage?.getItem(THEME_STORAGE_KEY) ?? null;
    if (isThemeMode(persistedTheme)) {
      return persistedTheme;
    }
  } catch {
    // Some browser modes can block localStorage; fall back to system preference.
  }

  return prefersDark() ? "dark" : "light";
}

export function applyTheme(theme: ThemeMode, root: ThemeRoot, storage: ThemeStorage | null | undefined) {
  root.dataset.theme = theme;

  try {
    storage?.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    // Theme switching should still work when persistence is unavailable.
  }
}
