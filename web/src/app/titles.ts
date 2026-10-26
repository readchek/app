// How publications are named and described, the same way as the iOS app,
// so a book reads the same on every screen and device.

import type { Progress, PublicationSummary } from "./client.ts"

const smallWords = new Set([
  "a",
  "an",
  "and",
  "as",
  "at",
  "but",
  "by",
  "for",
  "in",
  "of",
  "on",
  "or",
  "the",
  "to",
  "vs",
])

/** A title made from a file name, such as "peppercarrot_episode01". After the iOS app's BookImporter. */
export function titleFromFileName(name: string): string {
  // Underscores always break words; a dot or hyphen does unless it sits
  // between digits, as in "3.0" or "1-2".
  const spaced = [...name]
    .map((character, index, all) => {
      const inNumber =
        index > 0 &&
        index + 1 < all.length &&
        /\d/.test(all[index - 1]!) &&
        /\d/.test(all[index + 1]!)
      return character === "_" || ((character === "." || character === "-") && !inNumber)
        ? " "
        : character
    })
    .join("")
  const words = spaced.split(" ").filter(Boolean)
  if (words.length === 0) return name
  // Keep words that already have capitals, such as "MURAI" or "iPad", and
  // leave the small words of a title small, except at the start.
  return words
    .map((word, index) => {
      if (word !== word.toLowerCase()) return word
      if (index > 0 && smallWords.has(word)) return word
      return word.charAt(0).toUpperCase() + word.slice(1)
    })
    .join(" ")
}

// Files without metadata are titled by their file name on the server.
function readable(title: string): string {
  return title.includes(" ") ? title : titleFromFileName(title)
}

/** A publication's title, led by its number when the title doesn't say it, as in "3 · Dune Messiah". */
export function publicationTitle(publication: PublicationSummary): string {
  const title = readable(publication.title)
  const number = publication.numberLabel
  if (!number) return title
  return title.toLowerCase().includes(number.toLowerCase()) ? title : `${number} · ${title}`
}

/** The series a publication is in, or nothing for a book that's a series of its own. */
export function seriesTitle(publication: PublicationSummary): string | undefined {
  const series = readable(publication.series.title)
  return series.toLowerCase() === readable(publication.title).toLowerCase() ? undefined : series
}

/** Where you are, in a word or two: "Started", "34%" or "Finished". Nothing for something unopened. */
export function progressCaption(progress: Progress | undefined): string | undefined {
  if (!progress?.locator) return undefined
  const total = progress.locator.locations?.totalProgression
  if (total === undefined || total < 0.01) return "Started"
  if (total >= 1) return "Finished"
  return new Intl.NumberFormat(undefined, { style: "percent", maximumFractionDigits: 0 }).format(
    total,
  )
}
