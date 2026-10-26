// Covers and pages need the account's token, which an <img src> can't send,
// so they're fetched here and shown from object URLs. Fetched images are
// kept in the Cache API, keyed by their address without the token, so a
// return visit shows them at once.

import type { Account } from "./accounts.ts"

const cacheName = "chek-images-1"
// Covers change only when a file does. A week keeps them fresh enough
// without asking the server again on every visit.
const freshFor = 7 * 24 * 60 * 60 * 1000
const storedAt = "x-chek-stored-at"

const inFlight = new Map<string, Promise<Blob>>()

function openCache(): Promise<Cache | undefined> {
  // The Cache API exists only on https and localhost, which leaves out a
  // server's own page on a plain http home network. Those fetch each time.
  if (typeof caches === "undefined") return Promise.resolve(undefined)
  return caches.open(cacheName).catch(() => undefined)
}

async function fetchImage(account: Account, url: string): Promise<Blob> {
  const cache = await openCache()
  const cached = await cache?.match(url)
  if (cached && Date.now() - Number(cached.headers.get(storedAt)) < freshFor) {
    return cached.blob()
  }
  const response = await fetch(url, { headers: { Authorization: `Bearer ${account.token}` } })
  if (!response.ok) {
    // An image the server can't give now is better shown stale than not at all.
    if (cached) return cached.blob()
    throw new Error(`The server answered ${response.status} for an image.`)
  }
  const blob = await response.blob()
  if (cache) {
    const headers = new Headers({ "Content-Type": blob.type, [storedAt]: String(Date.now()) })
    void cache.put(url, new Response(blob, { headers })).catch(() => {})
  }
  return blob
}

/** An image from the account's server, by its API path. Concurrent asks for one image share a fetch. */
export function loadImage(account: Account, path: string): Promise<Blob> {
  const url = `${account.server}${path}`
  const key = `${account.token}\n${url}`
  let pending = inFlight.get(key)
  if (!pending) {
    pending = fetchImage(account, url).finally(() => inFlight.delete(key))
    inFlight.set(key, pending)
  }
  return pending
}

/** An image that changes each time it's asked for, such as a frame of the server's browser. It isn't kept. */
export async function loadLiveImage(account: Account, path: string): Promise<Blob> {
  const response = await fetch(`${account.server}${path}`, {
    cache: "no-store",
    headers: { Authorization: `Bearer ${account.token}` },
  })
  if (!response.ok) throw new Error(`The server answered ${response.status} for an image.`)
  return response.blob()
}

/** Forgets every kept image, such as when the last account signs out. */
export async function clearImages() {
  if (typeof caches !== "undefined") await caches.delete(cacheName).catch(() => false)
}
