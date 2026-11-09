import { createSignal } from "solid-js"
import {
  type BookPreferences,
  type ReadingDirection,
  type Spreads,
  defaultBookPreferences,
} from "@readchek/reader"
import type { ReadingMode } from "./modes.ts"

// Reading settings are this browser's, as they're each device's in the iOS
// app: a phone and a desktop want different layouts.

/** What's the same for every comic on this device. How each series reads is chosen per series. */
export type ComicSettings = { spreads: Spreads }

const comicKey = "chek.reader.comic"
const directionKey = "chek.reader.directions"
const modeKey = "chek.reader.modes"
const guessKey = "chek.reader.guesses"

function read<T>(key: string, fallback: T): T {
  try {
    const value = localStorage.getItem(key)
    return value ? { ...fallback, ...(JSON.parse(value) as T) } : fallback
  } catch {
    return fallback
  }
}

function write(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Storage can be refused; the setting lasts until reload.
  }
}

const [comic, setComic] = createSignal<ComicSettings>({
  spreads: read<ComicSettings>(comicKey, { spreads: "automatic" }).spreads,
})

export { comic as comicSettings }

export function changeComicSettings(change: Partial<ComicSettings>) {
  const next = { ...comic(), ...change }
  write(comicKey, next)
  setComic(next)
}

// How a series reads is chosen per series: a manga reads right to left
// and a webtoon scrolls while the rest of the shelf does neither, so one
// setting for every comic made fixing one series break another.
const [modes, setModes] = createSignal<Record<string, ReadingMode>>(read(modeKey, {}))

// Directions chosen before reading modes, which still say how to read
// their series.
const directions = read<Record<string, ReadingDirection>>(directionKey, {})

/** The reading mode chosen for a series. `series` names it with its server. */
export function seriesMode(series: string): ReadingMode {
  const chosen = modes()[series]
  if (chosen) return chosen
  const before = directions[series]
  return before === "rtl" ? "manga" : before === "ltr" ? "comic" : "automatic"
}

export function setSeriesMode(series: string, mode: ReadingMode) {
  const next = { ...modes(), [series]: mode }
  write(modeKey, next)
  setModes(next)
}

// What a series' pages looked like when nothing said how it reads, so
// its next chapter opens the same way without being looked at again.
const guessesKept = 500
let guesses = read<Record<string, "paged" | "scrolled">>(guessKey, {})

export function seriesGuess(series: string): "paged" | "scrolled" | undefined {
  return guesses[series]
}

export function setSeriesGuess(series: string, guess: "paged" | "scrolled") {
  if (guesses[series] === guess) return
  const { [series]: _, ...rest } = guesses
  const keys = Object.keys(rest)
  // Insertion order is age: the oldest go first.
  for (const old of keys.slice(0, Math.max(keys.length - guessesKept + 1, 0))) delete rest[old]
  guesses = { ...rest, [series]: guess }
  write(guessKey, guesses)
}

/** Book settings: the reader's own, with `automatic` following the app's light or dark look. */
export type BookSettings = Omit<BookPreferences, "theme"> & {
  theme: BookPreferences["theme"] | "automatic"
}

const bookKey = "chek.reader.book"

const [book, setBook] = createSignal<BookSettings>(
  read(bookKey, { ...defaultBookPreferences, theme: "automatic" }),
)

export { book as bookSettings }

export function changeBookSettings(change: Partial<BookSettings>) {
  const next = { ...book(), ...change }
  write(bookKey, next)
  setBook(next)
}

// Readers' comments: whether to show them at all, and whose to hide, by
// source. Both stay in this browser, as the iOS app keeps them per device.
const commentsKey = "chek.reader.comments"

type CommentSettings = { show: boolean; hidden: Record<string, string[]> }

const [commentSettings, setCommentSettings] = createSignal<CommentSettings>(
  read(commentsKey, { show: true, hidden: {} }),
)

export { commentSettings }

function changeCommentSettings(next: CommentSettings) {
  write(commentsKey, next)
  setCommentSettings(next)
}

export function showComments(show: boolean) {
  changeCommentSettings({ ...commentSettings(), show })
}

/** Hides, or shows again, every comment `name` writes on source `extensionId`. */
export function hideCommenter(extensionId: string, name: string, hidden: boolean) {
  const current = commentSettings()
  const names = (current.hidden[extensionId] ?? []).filter((one) => one !== name)
  if (hidden) names.push(name)
  changeCommentSettings({
    ...current,
    hidden: { ...current.hidden, [extensionId]: names },
  })
}

export function isHiddenCommenter(extensionId: string, name: string): boolean {
  return commentSettings().hidden[extensionId]?.includes(name) ?? false
}
