// Lets Chek open without a connection, as an installed app should. It
// keeps the app's own files only: books, pages and covers are already kept
// by the app in the Cache API, and requests to Chek servers pass through.

const version = "chek-app-1"
const scope = new URL(self.registration.scope)

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(version)
      .then((cache) => cache.add(new Request(scope.href, { cache: "reload" })))
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith("chek-app-") && name !== version)
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  )
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  const url = new URL(request.url)
  if (request.method !== "GET" || url.origin !== scope.origin || !url.href.startsWith(scope.href)) {
    return
  }
  if (request.mode === "navigate" && request.destination === "document") {
    event.respondWith(page(request))
  } else if (url.pathname.startsWith(`${scope.pathname}assets/`)) {
    event.respondWith(kept(request))
  } else {
    event.respondWith(fresh(request))
  }
})

// Every address is the same single page, so the latest one is kept for
// opening any address offline.
async function page(request) {
  try {
    const response = await fetch(request)
    if (response.ok) {
      const cache = await caches.open(version)
      await cache.put(scope.href, response.clone())
    }
    return response
  } catch (error) {
    const cached = await caches.match(scope.href)
    if (cached) return cached
    throw error
  }
}

// Built scripts and styles are named by their content, so a kept one never changes.
async function kept(request) {
  const cached = await caches.match(request)
  if (cached) return cached
  const response = await fetch(request)
  if (response.ok) {
    const cache = await caches.open(version)
    await cache.put(request, response.clone())
  }
  return response
}

// Fonts, icons and the reader's frame: from the network, or the kept copy offline.
async function fresh(request) {
  try {
    const response = await fetch(request)
    if (response.ok) {
      const cache = await caches.open(version)
      await cache.put(request, response.clone())
    }
    return response
  } catch (error) {
    const cached = await caches.match(request)
    if (cached) return cached
    throw error
  }
}
