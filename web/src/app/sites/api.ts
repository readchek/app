// The source routes of the Chek server API: a person's installed
// extensions, and the series, chapters and pages each one reads from its
// site. Typed after the server's openapi.yaml.

import type { Rating } from "../../api.ts"
import type { Account } from "../accounts.ts"
import { type Series, call, query } from "../client.ts"

export type ContentFormat = "images" | "epub" | "pdf"

export type InstalledExtension = {
  id: string
  name: string
  version: string
  repositoryId: number
  sites: string[]
  languages: string[]
  formats: ContentFormat[]
  installedAt: string
  /** False while it came from the person's own repository and the admin allows only the allow list. */
  usable: boolean
  /** The version the repository lists, when it differs from the installed one. */
  update: string | null
}

export type AvailableExtension = {
  repositoryId: number
  id: string
  name: string
  version: string
  sites: string[]
  languages: string[]
  capabilities: string[]
  formats: ContentFormat[]
  installedVersion: string | null
}

export type RemoteSeriesItem = {
  id: string
  title: string
  coverUrl: string | null
  contentRating: Rating | null
}

export type RemoteSeries = RemoteSeriesItem & {
  summary: string | null
  contributors: { name: string; role: string }[]
  readingDirection: "ltr" | "rtl" | "ttb" | null
  status: "ongoing" | "completed" | "hiatus" | "cancelled" | null
  year: number | null
  tags: string[]
}

export type RemoteRelease = {
  id: string
  title: string
  number: string | null
  version: string | null
  published: string | null
  language: string | null
  releaseGroup: string | null
  official: boolean
}

/** A chapter: its picked release's fields, and every release of it with the picked one first. */
export type RemoteChapter = RemoteRelease & { releases: RemoteRelease[] }

export type ChapterPage = {
  items: RemoteChapter[]
  offset: number
  nextOffset: number | null
  total: number
  chapterCount: number | null
  preferredGroup: string | null
}

export type Rights = {
  license: string | null
  licenseUrl: string | null
  attribution: string | null
  sourceUrl: string | null
}

export type ChapterContent = {
  format: ContentFormat
  pages: { index: number; url: string }[] | null
  file: {
    id: string
    mediaType: string
    url: string
    size: number | null
    fileName: string | null
  } | null
  rights: Rights | null
}

const base = (id: string) => `/api/v1/me/extensions/${encodeURIComponent(id)}`

export async function installedExtensions(
  account: Account,
  signal?: AbortSignal,
): Promise<InstalledExtension[]> {
  return (await call<{ items: InstalledExtension[] }>(account, "/api/v1/me/extensions", { signal }))
    .items
}

export async function availableExtensions(
  account: Account,
  signal?: AbortSignal,
): Promise<AvailableExtension[]> {
  return (await call<{ items: AvailableExtension[] }>(account, "/api/v1/extensions", { signal }))
    .items
}

/** Installs an extension, or updates it, from a repository. */
export function installExtension(
  account: Account,
  id: string,
  repositoryId: number,
): Promise<InstalledExtension> {
  return call(account, base(id), { method: "PUT", body: { repositoryId } })
}

export function uninstallExtension(account: Account, id: string): Promise<void> {
  return call(account, base(id), { method: "DELETE" })
}

/** One page of a site's series matching `q`, or the ones it shows first without it. Pages count from 1. */
export function searchSite(
  account: Account,
  id: string,
  options: { q?: string; page: number },
  signal?: AbortSignal,
): Promise<{ items: RemoteSeriesItem[]; hasMore: boolean }> {
  return call(account, `${base(id)}/search${query(options)}`, { signal })
}

export function siteSeries(
  account: Account,
  id: string,
  seriesId: string,
  signal?: AbortSignal,
): Promise<RemoteSeries> {
  return call(account, `${base(id)}/series${query({ seriesId })}`, { signal })
}

export type ChapterOrder = "asc" | "desc"

export function siteChapters(
  account: Account,
  id: string,
  options: {
    seriesId: string
    order?: ChapterOrder
    offset?: number
    after?: string
    limit?: number
  },
  signal?: AbortSignal,
): Promise<ChapterPage> {
  return call(account, `${base(id)}/chapters${query(options)}`, { signal })
}

/** Chooses whose releases a series shows first, on every device; null goes back to the default. */
export function setReleaseGroup(
  account: Account,
  id: string,
  seriesId: string,
  releaseGroup: string | null,
): Promise<void> {
  return call(account, `${base(id)}/release-group`, {
    method: "PUT",
    body: { seriesId, releaseGroup },
  })
}

export function chapterContent(
  account: Account,
  id: string,
  chapterId: string,
  signal?: AbortSignal,
): Promise<ChapterContent> {
  return call(account, `${base(id)}/content${query({ chapterId })}`, { signal })
}

/** Follows a series into an extension library, adding a publication per chapter. Admins only. */
export function followSeries(
  account: Account,
  libraryId: number,
  seriesId: string,
): Promise<Series> {
  return call(account, `/api/v1/libraries/${libraryId}/series`, {
    method: "POST",
    body: { seriesId },
  })
}

/** Makes a library that runs on an extension the admin installed. It starts empty. */
export function addExtensionLibrary(
  account: Account,
  name: string,
  extensionId: string,
): Promise<{ id: number; name: string }> {
  return call(account, "/api/v1/libraries", {
    method: "POST",
    body: { name, extension: { extensionId } },
  })
}

// The verification browser: a Chromium the server runs for this person,
// shown as frames and clicked through, for sites that check for a person.

export function startBrowser(account: Account, id: string, url: string): Promise<void> {
  return call(account, `${base(id)}/browser`, { method: "POST", body: { url } })
}

export function browserFramePath(id: string): string {
  return `${base(id)}/browser/frame`
}

export function clickBrowser(account: Account, id: string, x: number, y: number): Promise<void> {
  return call(account, `${base(id)}/browser/click`, { method: "POST", body: { x, y } })
}

export function resumeBrowser(account: Account, id: string): Promise<void> {
  return call(account, `${base(id)}/browser/resume`, { method: "POST" })
}

export function closeBrowser(account: Account, id: string): Promise<void> {
  return call(account, `${base(id)}/browser`, { method: "DELETE" })
}
