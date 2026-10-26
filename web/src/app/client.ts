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
}

export type Page<T> = { items: T[]; nextCursor?: string }

export type Continued = { publication: PublicationSummary; progress: Progress }

async function get<T>(account: Account, path: string, signal?: AbortSignal): Promise<T> {
  try {
    return await request<T>(account.server, path, { token: account.token, signal })
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) expire(account.server)
    throw error
  }
}

function query(params: Record<string, string | number | undefined>): string {
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
