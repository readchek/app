import { createSignal } from "solid-js"
import {
  type BookPreferences,
  type ComicFlow,
  type ReadingDirection,
  type Spreads,
  defaultBookPreferences,
} from "@readchek/reader"

// Reading settings are this browser's, as they're each device's in the iOS
// app: a phone and a desktop want different layouts.

export type ComicSettings = { flow: ComicFlow; spreads: Spreads }

const comicKey = "chek.reader.comic"
const directionKey = "chek.reader.directions"

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

const [comic, setComic] = createSignal<ComicSettings>(
  read(comicKey, { flow: "automatic", spreads: "automatic" }),
)

export { comic as comicSettings }

export function changeComicSettings(change: Partial<ComicSettings>) {
  const next = { ...comic(), ...change }
  write(comicKey, next)
  setComic(next)
}

// The direction is chosen per series, as on iOS: a manga series reads
// right to left while the rest of the shelf doesn't.
const [directions, setDirections] = createSignal<Record<string, ReadingDirection>>(
  read(directionKey, {}),
)

/** The direction chosen for a series, if any. `series` names it with its server. */
export function seriesDirection(series: string): ReadingDirection | undefined {
  return directions()[series]
}

export function setSeriesDirection(series: string, direction: ReadingDirection) {
  const next = { ...directions(), [series]: direction }
  write(directionKey, next)
  setDirections(next)
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
