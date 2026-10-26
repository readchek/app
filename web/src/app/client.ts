// The reading parts of the Chek server API, typed after the server's
// openapi.yaml. Every call goes through `get`, so a token the server no
// longer takes marks its account signed out wherever it happens.

import { ApiError, request } from "../api.ts"
import { type Account, expire } from "./accounts.ts"

export type Format =
  | "epub"
  | "pdf"
  | "cbz"
  | "cbt"
  | "cbr"
  | "cb7"
  | "mobi"
  | "azw3"
  | "fb2"
  | "txt"
  | "markdown"
  | "remote"

export type PublicationSummary = {
  id: number
  series: { id: number; title: string }
  title: string
  numberLabel: string | null
  format: Format
  pageCount: number | null
  available: boolean
  hasCover: boolean
}

/** A Readium Locator, as the server stores it. */
export type Locator = {
  href: string
  type: string
  title?: string
  locations?: {
    fragments?: string[]
    progression?: number
    totalProgression?: number
    position?: number
  }
  text?: { before?: string; highlight?: string; after?: string }
}

export type Progress = {
  revision: number
  locator: Locator | null
  device: string | null
  updatedAt: string | null
}

export type Library = {
  id: number
  name: string
  kind: "folder" | "source"
  /** Where a source library reads from; an extension library names its extension. */
  source?: { type: "komga" | "kavita" | "extension"; extensionId?: string }
}

export type Page<T> = { items: T[]; nextCursor?: string }

export type Continued = { publication: PublicationSummary; progress: Progress }

export type PublicationDetail = PublicationSummary & {
  contributors: { name: string; role: string | null }[]
  description: string | null
  publisher: string | null
  language: string | null
  published: string | null
  readingDirection: "ltr" | "rtl" | null
}

export type PageInfo = { index: number; mediaType: string; size: number | null }

/** Formats read as pages, in the comic reader. */
export const comicFormats: readonly Format[] = ["cbz", "cbt", "cbr", "cb7", "remote"]

export async function call<T>(
  account: Account,
  path: string,
  init: { method?: string; body?: unknown; signal?: AbortSignal } = {},
): Promise<T> {
  try {
    return await request<T>(account.server, path, { ...init, token: account.token })
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) expire(account.server)
    throw error
  }
}

function get<T>(account: Account, path: string, signal?: AbortSignal): Promise<T> {
  return call<T>(account, path, { signal })
}

export function query(params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams()
  for (const [name, value] of Object.entries(params)) {
    if (value !== undefined) search.set(name, String(value))
  }
  const text = search.toString()
  return text ? `?${text}` : ""
}

export function libraries(account: Account, signal?: AbortSignal): Promise<Page<Library>> {
  return get(account, "/api/v1/libraries", signal)
}

export function continueReading(
  account: Account,
  options: { cursor?: string; limit?: number } = {},
  signal?: AbortSignal,
): Promise<Page<Continued>> {
  return get(account, `/api/v1/me/continue-reading${query(options)}`, signal)
}

export function recentlyAdded(
  account: Account,
  options: { libraryId?: number; cursor?: string; limit?: number } = {},
  signal?: AbortSignal,
): Promise<Page<PublicationSummary>> {
  return get(account, `/api/v1/recently-added${query(options)}`, signal)
}

export function coverPath(publication: { id: number }): string {
  return `/api/v1/publications/${publication.id}/cover`
}

export function publication(
  account: Account,
  id: number,
  signal?: AbortSignal,
): Promise<PublicationDetail> {
  return get(account, `/api/v1/publications/${id}`, signal)
}

export async function pages(
  account: Account,
  id: number,
  signal?: AbortSignal,
): Promise<PageInfo[]> {
  return (await get<{ items: PageInfo[] }>(account, `/api/v1/publications/${id}/pages`, signal))
    .items
}

export function pagePath(publicationId: number, index: number): string {
  return `/api/v1/publications/${publicationId}/pages/${index}`
}

export function seriesPublications(
  account: Account,
  seriesId: number,
  options: { cursor?: string; limit?: number } = {},
  signal?: AbortSignal,
): Promise<Page<PublicationSummary>> {
  return get(account, `/api/v1/series/${seriesId}/publications${query(options)}`, signal)
}

export function progress(account: Account, id: number, signal?: AbortSignal): Promise<Progress> {
  return get(account, `/api/v1/publications/${id}/progress`, signal)
}

/** Another device saved a position since this one last read it. */
export class ProgressConflict extends Error {
  constructor(readonly current: Progress) {
    super("Another device saved a newer position.")
  }
}

/** Saves a position if no other device saved since `expectedRevision`; otherwise throws `ProgressConflict`. */
export async function saveProgress(
  account: Account,
  id: number,
  expectedRevision: number,
  locator: Locator,
): Promise<Progress> {
  try {
    return await call<Progress>(account, `/api/v1/publications/${id}/progress`, {
      method: "PUT",
      body: { expectedRevision, locator },
    })
  } catch (error) {
    if (error instanceof ApiError && error.code === "progress_conflict" && error.body) {
      throw new ProgressConflict((error.body as { current: Progress }).current)
    }
    throw error
  }
}

export type Series = {
  id: number
  libraryId: number
  title: string
  publicationCount: number
  coverPublicationId: number | null
}

export function librarySeries(
  account: Account,
  libraryId: number,
  options: { cursor?: string; limit?: number } = {},
  signal?: AbortSignal,
): Promise<Page<Series>> {
  return get(account, `/api/v1/libraries/${libraryId}/series${query(options)}`, signal)
}

export function series(account: Account, id: number, signal?: AbortSignal): Promise<Series> {
  return get(account, `/api/v1/series/${id}`, signal)
}

export function search(
  account: Account,
  options: { q: string; libraryId?: number; cursor?: string; limit?: number },
  signal?: AbortSignal,
): Promise<Page<PublicationSummary>> {
  return get(account, `/api/v1/search${query(options)}`, signal)
}
