import { createSignal } from "solid-js"

// Recent searches, kept in this browser as the iOS app keeps them on the
// device. The search field adds to them and the results screen lists them.

const recentKey = "chek.recentSearches"
const recentCount = 8

function stored(): string[] {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(recentKey) ?? "[]")
    return Array.isArray(value)
      ? value.filter((item): item is string => typeof item === "string")
      : []
  } catch {
    return []
  }
}

const [recent, setRecent] = createSignal(stored())

export { recent as recentSearches }

export function keepRecentSearch(value: string) {
  const next = [value, ...recent().filter((item) => item !== value)].slice(0, recentCount)
  try {
    localStorage.setItem(recentKey, JSON.stringify(next))
  } catch {
    // Recent searches are only a convenience.
  }
  setRecent(next)
}

export function clearRecentSearches() {
  try {
    localStorage.removeItem(recentKey)
  } catch {
    // Nothing was stored.
  }
  setRecent([])
}
