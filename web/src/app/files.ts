// Books are read from their whole file, downloaded with the account's token
// and kept in the Cache API, so opening a book again doesn't download it
// again. The server's CORS doesn't let the browser revalidate, so a kept
// file is used for a while and then fetched fresh.

import type { Account } from "./accounts.ts"

const cacheName = "chek-files-1"
// Files change rarely: a fixed edition, or a new scan of one.
const freshFor = 3 * 24 * 60 * 60 * 1000
const storedAt = "x-chek-stored-at"

/** A file from the account's server, by its API path, kept for next time. */
export async function loadFile(
  account: Account,
  path: string,
  signal?: AbortSignal,
): Promise<Blob> {
  const url = `${account.server}${path}`
  const cache =
    typeof caches === "undefined" ? undefined : await caches.open(cacheName).catch(() => undefined)
  const cached = await cache?.match(url)
  if (cached && Date.now() - Number(cached.headers.get(storedAt)) < freshFor) {
    return cached.blob()
  }
  let response: Response
  try {
    response = await fetch(url, {
      signal,
      headers: { Authorization: `Bearer ${account.token}` },
    })
  } catch (error) {
    if (cached) return cached.blob()
    throw error
  }
  if (!response.ok) {
    if (cached) return cached.blob()
    throw new Error(
      response.status === 404
        ? "The server no longer has this book's file."
        : `The server answered ${response.status} for this book's file.`,
    )
  }
  const blob = await response.blob()
  if (cache) {
    const headers = new Headers({ "Content-Type": blob.type, [storedAt]: String(Date.now()) })
    void cache.put(url, new Response(blob, { headers })).catch(() => {})
  }
  return blob
}

/** Forgets every kept file, such as when the last account signs out. */
export async function clearFiles() {
  if (typeof caches !== "undefined") await caches.delete(cacheName).catch(() => false)
}
