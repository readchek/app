// The demo's Chek server: answers the API from a snapshot of a real
// server's libraries (scripts/demo-snapshot.ts), whose files are served
// beside the app in /demo-data/. The demo build runs it in the browser
// (server.ts), and the demo's Worker runs it for apps (worker.ts).

import type {
  Continued,
  Library,
  Locator,
  PageInfo,
  Progress,
  PublicationDetail,
  Series,
} from "../app/client.ts"
import type { User } from "../api.ts"

export type Catalog = {
  server: object
  user: User
  contentRatings: string[]
  libraries: Library[]
  series: Series[]
  seriesPublications: Record<string, number[]>
  publications: Record<string, PublicationDetail>
  pages: Record<string, PageInfo[]>
  recent: number[]
  extensions: object[]
  available: object[]
  sites: Record<string, Site>
  files: Record<string, { name: string; type: string }>
}

type Site = {
  listing: { id: string; title: string }[]
  series: Record<string, object>
  chapters: Record<
    string,
    { items: { id: string }[]; chapterCount: number | null; preferredGroup: string | null }
  >
  contents: Record<string, object>
}

/** Where the demo keeps reading positions. */
export type Positions = {
  all(): Record<string, Progress>
  save(id: string, progress: Progress): void
}

/** What the demo's server runs on. */
export type Backend = {
  catalog: Catalog
  positions: Positions
  /** A file of the snapshot's, by its name in /demo-data/files. */
  file(name: string, request: Request): Promise<Response>
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

function error(status: number, code: string, message: string): Response {
  return json({ code, message }, status)
}

const missing = () => error(404, "not_found", "the demo doesn't have this")

const notInDemo = () =>
  error(
    404,
    "not_in_demo",
    "the demo keeps only the first chapters of each series. Run your own Chek server to read the rest",
  )

// The server's own words for a demo account, which can't be changed.
const unchangeable = () =>
  error(403, "demo_account", "this is a shared demo account, which can't be changed")

/** One page of `items`, from the offset in the request's cursor, as the server pages lists. */
function paged<T>(items: T[], url: URL, fallback = 50): Response {
  const offset = Number(url.searchParams.get("cursor") ?? 0) || 0
  const limit = Number(url.searchParams.get("limit") ?? fallback) || fallback
  const next = offset + limit
  return json({
    items: items.slice(offset, next),
    ...(next < items.length ? { nextCursor: String(next) } : {}),
  })
}

function file(backend: Backend, request: Request, path: string): Promise<Response> {
  const stored = backend.catalog.files[path]
  return stored ? backend.file(stored.name, request) : Promise.resolve(missing())
}

function progressOf(backend: Backend, id: string): Progress {
  return (
    backend.positions.all()[id] ?? { revision: 0, locator: null, device: null, updatedAt: null }
  )
}

/** Text folded for matching: lowercase, without accents. */
function folded(text: string): string {
  return text.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase()
}

function matches(query: string, ...texts: string[]): boolean {
  const haystack = folded(texts.join(" "))
  return folded(query)
    .split(/\s+/)
    .filter(Boolean)
    .every((word) => haystack.includes(word))
}

/** The demo server's answer to one request to the API. */
export async function answer(request: Request, backend: Backend): Promise<Response> {
  const url = new URL(request.url)
  const catalog = backend.catalog
  if (url.pathname === "/health") return json({ status: "ok" })
  const path = url.pathname.slice("/api/v1".length)
  const method = request.method
  const parts = path.split("/").filter(Boolean)
  const publications = catalog.publications

  if (method === "POST" && (path === "/auth/sign-in" || path === "/auth/web-link")) {
    return json({ token: "demo", user: catalog.user })
  }
  if (method === "POST" && path === "/auth/sign-out") return new Response(null, { status: 204 })
  // The iOS app opens the web app signed in with a one-time code, which the
  // demo takes whatever it is.
  if (method === "POST" && path === "/me/web-link") {
    return json({ code: "demo", expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString() })
  }

  if (method === "GET") {
    switch (path) {
      case "/server":
        return json(catalog.server)
      case "/me":
        return json(catalog.user)
      case "/me/content-ratings":
        return json({ contentRatings: catalog.contentRatings })
      case "/me/sessions": {
        const now = new Date()
        const expires = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000)
        return json([
          {
            id: 1,
            device: "Chek on the web",
            createdAt: now.toISOString(),
            lastUsedAt: now.toISOString(),
            expiresAt: expires.toISOString(),
            current: true,
          },
        ])
      }
      case "/me/identities":
        return json([])
      case "/libraries":
        return json({ items: catalog.libraries })
      case "/recently-added": {
        const library = Number(url.searchParams.get("libraryId")) || undefined
        const libraryOf = (id: number) =>
          catalog.series.find((series) => series.id === publications[id]?.series.id)?.libraryId
        const items = catalog.recent
          .filter((id) => library === undefined || libraryOf(id) === library)
          .map((id) => publications[id])
        return paged(items, url)
      }
      case "/me/continue-reading": {
        const saved = backend.positions.all()
        const items: Continued[] = Object.entries(saved)
          .filter(
            ([id, progress]) =>
              publications[id] &&
              progress.locator &&
              (progress.locator.locations?.totalProgression ?? 0) < 1,
          )
          .sort(([, a], [, b]) => (b.updatedAt ?? "").localeCompare(a.updatedAt ?? ""))
          .map(([id, progress]) => ({ publication: publications[id]!, progress }))
        return paged(items, url)
      }
      case "/search": {
        const q = url.searchParams.get("q") ?? ""
        const library = Number(url.searchParams.get("libraryId")) || undefined
        const items = Object.values(publications)
          .filter((publication) => {
            const series = catalog.series.find((one) => one.id === publication.series.id)
            return (
              (library === undefined || series?.libraryId === library) &&
              matches(
                q,
                publication.title,
                publication.series.title,
                ...publication.contributors.map((person) => person.name),
              )
            )
          })
          .sort((a, b) => a.title.localeCompare(b.title))
        return paged(items, url)
      }
      case "/me/extensions":
        return json({ items: catalog.extensions })
      case "/extensions":
        return json({ items: catalog.available })
    }

    if (parts[0] === "libraries" && parts[2] === "series" && parts.length === 3) {
      const id = Number(parts[1])
      return paged(
        catalog.series.filter((series) => series.libraryId === id),
        url,
      )
    }
    if (parts[0] === "series" && parts.length === 2) {
      const series = catalog.series.find((one) => one.id === Number(parts[1]))
      return series ? json(series) : missing()
    }
    if (parts[0] === "series" && parts[2] === "publications") {
      const ids = catalog.seriesPublications[parts[1]!]
      return ids
        ? paged(
            ids.map((id) => publications[id]),
            url,
          )
        : missing()
    }
    if (parts[0] === "publications") {
      const id = parts[1]!
      if (!publications[id]) return missing()
      switch (parts[2]) {
        case undefined:
          return json(publications[id])
        case "pages":
          if (parts[3] === undefined) return json({ items: catalog.pages[id] ?? [] })
          return file(backend, request, `/api/v1${path}`)
        case "cover":
        case "file":
          return file(backend, request, `/api/v1${path}`)
        case "progress":
          return json(progressOf(backend, id))
      }
    }
  }

  if (method === "PUT" && parts[0] === "publications" && parts[2] === "progress") {
    const id = parts[1]!
    if (!publications[id]) return missing()
    const body = (await request.json()) as { expectedRevision: number; locator: Locator }
    const current = progressOf(backend, id)
    if (body.expectedRevision !== current.revision) {
      return json(
        {
          code: "progress_conflict",
          message: `progress is at revision ${current.revision}, not ${body.expectedRevision}; choose a position and save again with that revision`,
          current,
        },
        409,
      )
    }
    const saved: Progress = {
      revision: current.revision + 1,
      locator: body.locator,
      device: "Chek on the web",
      updatedAt: new Date().toISOString(),
    }
    backend.positions.save(id, saved)
    return json(saved)
  }

  if (parts[0] === "me" && parts[1] === "extensions" && parts[2]) {
    return site(request, url, backend, decodeURIComponent(parts[2]), parts.slice(3).join("/"))
  }

  // The demo's account is a reader, so it can't reach the admin panel, and
  // it can't change anything about itself.
  return method === "GET" ? missing() : unchangeable()
}

async function site(
  request: Request,
  url: URL,
  backend: Backend,
  id: string,
  rest: string,
): Promise<Response> {
  const site = backend.catalog.sites[id]
  if (request.method === "PUT" && rest === "release-group") {
    return new Response(null, { status: 204 })
  }
  if (!site || request.method !== "GET") return unchangeable()
  const params = url.searchParams
  switch (rest) {
    case "search": {
      const q = params.get("q") ?? ""
      const page = Number(params.get("page") ?? 1)
      return json({
        items: page > 1 ? [] : site.listing.filter((item) => matches(q, item.title)),
        hasMore: false,
      })
    }
    case "series": {
      const series = site.series[params.get("seriesId") ?? ""]
      return series ? json(series) : missing()
    }
    case "chapters": {
      const recorded = site.chapters[params.get("seriesId") ?? ""]
      if (!recorded) return missing()
      let items = recorded.items
      const after = params.get("after")
      if (after) items = items.slice(items.findIndex((item) => item.id === after) + 1)
      if (params.get("order") === "desc") items = [...items].reverse()
      const offset = Number(params.get("offset") ?? 0) || 0
      const limit = Number(params.get("limit") ?? 100) || 100
      const next = offset + limit
      return json({
        items: items.slice(offset, next),
        offset,
        nextOffset: next < items.length ? next : null,
        total: items.length,
        chapterCount: recorded.chapterCount,
        preferredGroup: recorded.preferredGroup,
      })
    }
    case "pages": {
      const content = site.contents[params.get("chapterId") ?? ""] as
        | { pages: { index: number; url: string }[] | null }
        | undefined
      return content?.pages ? json({ items: content.pages }) : notInDemo()
    }
    case "content": {
      const content = site.contents[params.get("chapterId") ?? ""]
      return content ? json(content) : notInDemo()
    }
  }
  // Covers, pages and files the site gave, by their whole address.
  return file(backend, request, url.pathname + url.search)
}
