import type { ComicFlow, ReadingDirection } from "@readchek/reader"

// How a comic is read comes down to one choice, the way readers think of
// it: a comic, a manga or a webtoon. The layout and the direction follow
// from it, so nobody has to set two things to fix one series.

/** How a series is read. `automatic` follows what its source says, then how its pages look. */
export type ReadingMode = "automatic" | "comic" | "manga" | "webtoon"

/** Which way a source says a series reads; `ttb` is a vertical strip. */
export type SourceDirection = "ltr" | "rtl" | "ttb" | null

export type Layout = {
  flow: ComicFlow
  direction: ReadingDirection
  /** What the layout amounts to, for saying which one Automatic chose. Undefined while the pages decide. */
  reads: Exclude<ReadingMode, "automatic"> | undefined
}

/**
 * The layout for a series: the reader's own choice first, then what the
 * source says, then what the pages looked like last time, and only then
 * a look at the pages themselves.
 */
export function layoutFor(
  mode: ReadingMode,
  source: SourceDirection,
  guess: "paged" | "scrolled" | undefined,
): Layout {
  switch (mode) {
    case "comic":
      return { flow: "paged", direction: "ltr", reads: "comic" }
    case "manga":
      return { flow: "paged", direction: "rtl", reads: "manga" }
    case "webtoon":
      return { flow: "scrolled", direction: "ltr", reads: "webtoon" }
    case "automatic":
      if (source === "ttb") return { flow: "scrolled", direction: "ltr", reads: "webtoon" }
      // Right to left is something a source says on purpose, and means pages.
      if (source === "rtl") return { flow: "paged", direction: "rtl", reads: "manga" }
      // Left to right is also what sources say when they don't know, so
      // the pages still get a say.
      if (guess === "scrolled") return { flow: "scrolled", direction: "ltr", reads: "webtoon" }
      if (guess === "paged") return { flow: "paged", direction: "ltr", reads: "comic" }
      return { flow: "automatic", direction: "ltr", reads: undefined }
  }
}

/** What each mode is called, and in a few words what it does. */
export const modeNames: Record<
  Exclude<ReadingMode, "automatic">,
  { name: string; does: string }
> = {
  comic: { name: "Comic", does: "Pages turn left to right." },
  manga: { name: "Manga", does: "Pages turn right to left." },
  webtoon: { name: "Webtoon", does: "One long page to scroll." },
}
