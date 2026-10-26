import type { RemoteRelease } from "./api.ts"

/** A chapter's name as a list shows it: its number, and its title when that says more. */
export function chapterTitle(chapter: RemoteRelease): string {
  const title = chapter.title.trim()
  if (!chapter.number) return title || "Chapter"
  const numbered = `Chapter ${chapter.number}`
  // Many sites title a chapter only with its number.
  if (!title || title === chapter.number || title.toLowerCase() === numbered.toLowerCase()) {
    return numbered
  }
  // Others already lead with it, as "Episode 1: The Potion of Flight" does.
  if (title.includes(chapter.number)) return title
  return `${numbered}: ${title}`
}

const statusLabels = {
  ongoing: "Ongoing",
  completed: "Completed",
  hiatus: "On hiatus",
  cancelled: "Cancelled",
} as const

export function statusLabel(status: keyof typeof statusLabels | null): string | undefined {
  return status ? statusLabels[status] : undefined
}

/** A site's address without a wildcard, for showing and for opening it in the server's browser. */
export function siteHost(site: string): string {
  return site.replace(/^\*\./, "")
}
