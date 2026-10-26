import type { Account } from "../accounts.ts"
import type { Page } from "../client.ts"
import {
  type ChapterOrder,
  type InstalledExtension,
  type RemoteChapter,
  type RemoteSeriesItem,
  availableExtensions,
  installedExtensions,
  searchSite,
  siteChapters,
} from "./api.ts"

/** An installed extension, with what it needs beyond plain requests from its repository's index. */
export type SiteInfo = InstalledExtension & { capabilities: string[] }

export async function siteInfo(account: Account, id: string): Promise<SiteInfo> {
  const [installed, available] = await Promise.all([
    installedExtensions(account),
    // Only the repository's index says what an extension needs, and a
    // repository that can't be read shouldn't stop the site opening.
    availableExtensions(account).catch(() => []),
  ])
  const extension = installed.find((item) => item.id === id)
  if (!extension) throw new Error("This site isn't added on this server. Add it from Sites.")
  const listed = available.find(
    (item) => item.id === id && item.repositoryId === extension.repositoryId,
  )
  return { ...extension, capabilities: listed?.capabilities ?? [] }
}

// Sites page by number and chapters by offset; the paged lists page by
// cursor, so each is told its next page as one.

export async function siteSeriesPage(
  account: Account,
  id: string,
  q: string | undefined,
  cursor: string | undefined,
  signal: AbortSignal,
): Promise<Page<RemoteSeriesItem>> {
  const page = cursor ? Number(cursor) : 1
  const answer = await searchSite(account, id, { q, page }, signal)
  return { items: answer.items, nextCursor: answer.hasMore ? String(page + 1) : undefined }
}

export async function chapterPage(
  account: Account,
  id: string,
  seriesId: string,
  order: ChapterOrder,
  cursor: string | undefined,
  signal: AbortSignal,
  told: (page: {
    total: number
    chapterCount: number | null
    preferredGroup: string | null
  }) => void,
): Promise<Page<RemoteChapter>> {
  const answer = await siteChapters(
    account,
    id,
    { seriesId, order, offset: cursor ? Number(cursor) : 0, limit: 100 },
    signal,
  )
  told(answer)
  return {
    items: answer.items,
    nextCursor: answer.nextOffset === null ? undefined : String(answer.nextOffset),
  }
}
