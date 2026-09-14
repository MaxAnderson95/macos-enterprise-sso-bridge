/**
 * Gecko's promise-returning namespace is `browser`; Chromium defines only `chrome`,
 * whose MV3 methods return promises. Preferring `browser` means both engines hand back
 * a promise, rather than relying on Gecko's callback-shaped `chrome` alias.
 */
export function engineApi(): typeof chrome {
  return (globalThis as { browser?: typeof chrome }).browser ?? chrome;
}
