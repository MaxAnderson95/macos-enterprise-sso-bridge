import type { SessionArea } from "../../src/tabSession";

/**
 * A `storage.session` stand-in that outlives the module reading it, which is the point:
 * the browser's area belongs to the browser context, not to the service worker, so a
 * test that builds a second `tabSession` over the same area is asking the same question
 * an eviction asks.
 */
export function fakeSessionArea() {
  const items = new Map<string, unknown>();
  const area: SessionArea = {
    get: async (keys) =>
      Object.fromEntries(keys.filter((key) => items.has(key)).map((key) => [key, items.get(key)])),
    set: async (entries) => {
      for (const [key, value] of Object.entries(entries)) {
        items.set(key, value);
      }
    },
    remove: async (keys) => {
      for (const key of keys) {
        items.delete(key);
      }
    },
  };
  return { area, items };
}
