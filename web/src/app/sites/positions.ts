import { createSignal } from "solid-js"
import type { Locator } from "../client.ts"

// Your place in chapters read straight from a site. The server keeps no
// positions for those, only for series followed into a library, so this
// browser keeps them, as the iOS app keeps them on the device.

/** Where you are in one site chapter. `server` is the account's key. */
export type SitePosition = {
  server: string
  extensionId: string
  seriesId: string
  seriesTitle: string
  chapterId: string
  chapterTitle: string
  /** The series' cover as a path on the server, for Continue Reading. */
  coverUrl: string | null
  direction: "ltr" | "rtl" | null
  locator: Locator
  /** How far through the chapter, from 0 to 1. */
  progression: number
  openedAt: string
}

const storageKey = "chek.sitePositions"
// Enough for a long history without the store growing for ever.
const kept = 1000

function stored(): Record<string, SitePosition> {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(storageKey) ?? "{}")
    return value && typeof value === "object" ? (value as Record<string, SitePosition>) : {}
  } catch {
    return {}
  }
}

const [positions, setPositions] = createSignal(stored())

// Another tab reading on moves this one's places too.
window.addEventListener("storage", (event) => {
  if (event.key === storageKey) setPositions(stored())
})

function key(server: string, extensionId: string, chapterId: string) {
  return `${server}\n${extensionId}\n${chapterId}`
}

export function chapterPosition(
  server: string,
  extensionId: string,
  chapterId: string,
): SitePosition | undefined {
  return positions()[key(server, extensionId, chapterId)]
}

export function savePosition(position: SitePosition) {
  const next = {
    ...positions(),
    [key(position.server, position.extensionId, position.chapterId)]: position,
  }
  const keys = Object.keys(next)
  if (keys.length > kept) {
    keys
      .sort((a, b) => next[a]!.openedAt.localeCompare(next[b]!.openedAt))
      .slice(0, keys.length - kept)
      .forEach((old) => delete next[old])
  }
  try {
    localStorage.setItem(storageKey, JSON.stringify(next))
  } catch {
    // Storage can be refused; the place lasts until the tab closes.
  }
  setPositions(next)
}

/** The chapter of a series you opened last, if any. */
export function lastInSeries(
  server: string,
  extensionId: string,
  seriesId: string,
): SitePosition | undefined {
  return Object.values(positions())
    .filter((p) => p.server === server && p.extensionId === extensionId && p.seriesId === seriesId)
    .sort((a, b) => b.openedAt.localeCompare(a.openedAt))[0]
}

// A series whose last chapter you finished stays a while, so its next
// chapter is a tap away, then leaves.
const finishedFor = 14 * 24 * 60 * 60 * 1000

/** The chapter you were last in for each site series you're reading, newest first. */
export function continuingSiteSeries(): SitePosition[] {
  const latest = new Map<string, SitePosition>()
  for (const position of Object.values(positions())) {
    const series = `${position.server}\n${position.extensionId}\n${position.seriesId}`
    const before = latest.get(series)
    if (!before || before.openedAt < position.openedAt) latest.set(series, position)
  }
  return [...latest.values()]
    .filter(
      (position) =>
        position.progression < 1 || Date.now() - Date.parse(position.openedAt) < finishedFor,
    )
    .sort((a, b) => b.openedAt.localeCompare(a.openedAt))
}
