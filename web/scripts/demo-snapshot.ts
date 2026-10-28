// Records what the demo shows from a Chek server: its libraries, series,
// books and sites, with every cover, page and file the web app would load.
// The demo build answers the app's requests from this snapshot in the
// browser, so the demo needs no server of its own.
//
//   bun scripts/demo-snapshot.ts <server> <name> <password> [out]
//
// Run it against a server seeded by readchek/chek's deploy/demo, then pack
// the folder with scripts/demo-pack.ts. Files already kept in `out` are
// kept again without asking, so an interrupted run picks up where it was.
import { createHash } from "node:crypto"
import { mkdir } from "node:fs/promises"
import { resolve } from "node:path"

const [server, name, password, out = resolve(import.meta.dir, "../demo-data")] = Bun.argv.slice(2)
if (!server || !name || !password) {
  console.error("Usage: bun scripts/demo-snapshot.ts <server> <name> <password> [out]")
  process.exit(1)
}

// Sites are read through the server from the sites themselves, so only the
// first chapters of the first series are kept, enough to show reading one.
const siteSeriesLimit = 12
const siteChapterLimit = 3

// Some hosts turn away requests that don't name a browser.
const agent = "Mozilla/5.0 (Chek demo snapshot)"

const token = (
  (await (
    await fetch(`${server}/api/v1/auth/sign-in`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "User-Agent": agent },
      body: JSON.stringify({ name, password, device: "Demo snapshot" }),
    })
  ).json()) as { token: string }
).token

async function answer(path: string): Promise<Response> {
  for (let attempt = 1; ; attempt++) {
    const response = await fetch(`${server}${path}`, {
      headers: { Authorization: `Bearer ${token}`, "User-Agent": agent },
    })
    if (response.ok || attempt === 3 || response.status < 500) return response
    await Bun.sleep(1000 * attempt)
  }
}

async function get<T>(path: string): Promise<T> {
  const response = await answer(path)
  if (!response.ok) throw new Error(`${path} answered ${response.status}`)
  return (await response.json()) as T
}

/** Every item of a cursor-paged list. */
async function all<T>(path: string): Promise<T[]> {
  const items: T[] = []
  let cursor: string | undefined
  do {
    const join = path.includes("?") ? "&" : "?"
    const page = await get<{ items: T[]; nextCursor?: string }>(
      `${path}${join}limit=100${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`,
    )
    items.push(...page.items)
    cursor = page.nextCursor
  } while (cursor)
  return items
}

const extensions: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
  "image/avif": "avif",
  "application/epub+zip": "epub",
  "application/pdf": "pdf",
}

type Stored = { name: string; type: string }
const index = Bun.file(resolve(out, "files.json"))
const files: Record<string, Stored> = (await index.exists()) ? await index.json() : {}
await mkdir(resolve(out, "files"), { recursive: true })

/** Keeps the file the server gives for `path`, named by its content so repeats are kept once. */
async function keep(path: string): Promise<void> {
  if (files[path]) return
  const response = await answer(path)
  if (!response.ok) {
    console.warn(`skipped ${path}: ${response.status}`)
    return
  }
  const type = (response.headers.get("Content-Type") ?? "application/octet-stream").split(";")[0]!
  const bytes = new Uint8Array(await response.arrayBuffer())
  const hash = createHash("sha256").update(bytes).digest("hex").slice(0, 24)
  const file = `${hash}.${extensions[type] ?? "bin"}`
  await Bun.write(resolve(out, "files", file), bytes)
  files[path] = { name: file, type }
  await Bun.write(index, JSON.stringify(files))
}

/** Runs `work` over `items`, a few at a time. */
async function each<T>(items: T[], work: (item: T) => Promise<void>, width = 6): Promise<void> {
  const queue = [...items]
  await Promise.all(
    Array.from({ length: width }, async () => {
      for (let item = queue.shift(); item !== undefined; item = queue.shift()) await work(item)
    }),
  )
}

type Summary = { id: number; format: string; hasCover: boolean }
type Series = { id: number; libraryId: number }

const user = await get<object>("/api/v1/me")
const version = await get<object>("/api/v1/server")
const { contentRatings } = await get<{ contentRatings: string[] }>("/api/v1/me/content-ratings")
// Where the libraries live on the server is no business of the demo's.
const libraries = (
  await get<{ items: { id: number; path?: string; scan?: unknown }[] }>("/api/v1/libraries")
).items.map(({ path: _path, scan: _scan, ...library }) => library)

const series: Series[] = []
for (const library of libraries)
  series.push(...(await all<Series>(`/api/v1/libraries/${library.id}/series`)))

const seriesPublications: Record<number, number[]> = {}
const publications: Record<number, Summary> = {}
const pages: Record<number, { index: number; mediaType: string }[]> = {}
await each(series, async (one) => {
  const items = await all<Summary>(`/api/v1/series/${one.id}/publications`)
  seriesPublications[one.id] = items.map((item) => item.id)
  for (const item of items) publications[item.id] = await get(`/api/v1/publications/${item.id}`)
})

const comic = new Set(["cbz", "cbt", "cbr", "cb7"])
await each(Object.values(publications), async (publication) => {
  console.log(`book ${publication.id}`)
  if (publication.hasCover) await keep(`/api/v1/publications/${publication.id}/cover`)
  if (comic.has(publication.format)) {
    pages[publication.id] = (
      await get<{ items: { index: number; mediaType: string }[] }>(
        `/api/v1/publications/${publication.id}/pages`,
      )
    ).items
    for (const page of pages[publication.id]!) {
      await keep(`/api/v1/publications/${publication.id}/pages/${page.index}`)
    }
  } else {
    await keep(`/api/v1/publications/${publication.id}/file`)
  }
})

const recent = (await all<Summary>("/api/v1/recently-added")).map((item) => item.id)

type SiteItem = { id: string; coverUrl: string | null }
type Chapter = { id: string }
type Content = { pages: { url: string }[] | null; file: { url: string } | null }
const installed = (await get<{ items: { id: string }[] }>("/api/v1/me/extensions")).items
const available = (await get<{ items: object[] }>("/api/v1/extensions")).items
const sites: Record<string, unknown> = {}
for (const extension of installed) {
  const base = `/api/v1/me/extensions/${encodeURIComponent(extension.id)}`
  const listing = (await get<{ items: SiteItem[] }>(`${base}/search?page=1`)).items.slice(
    0,
    siteSeriesLimit,
  )
  const details: Record<string, SiteItem> = {}
  const chapters: Record<string, unknown> = {}
  const contents: Record<string, Content> = {}
  for (const item of listing) {
    console.log(`site ${extension.id} ${item.id}`)
    if (item.coverUrl) await keep(item.coverUrl)
    const seriesId = encodeURIComponent(item.id)
    details[item.id] = await get(`${base}/series?seriesId=${seriesId}`)
    const found: Chapter[] = []
    let first: { chapterCount: number | null; preferredGroup: string | null } | undefined
    for (let offset: number | null = 0; offset !== null;) {
      const page: {
        items: Chapter[]
        nextOffset: number | null
        chapterCount: number | null
        preferredGroup: string | null
      } = await get(`${base}/chapters?seriesId=${seriesId}&order=asc&offset=${offset}&limit=100`)
      first ??= page
      found.push(...page.items)
      offset = page.nextOffset
    }
    chapters[item.id] = { ...first, items: found }
    for (const chapter of found.slice(0, siteChapterLimit)) {
      const content = await get<Content>(
        `${base}/content?chapterId=${encodeURIComponent(chapter.id)}`,
      )
      contents[chapter.id] = content
      await each(content.pages ?? [], (page) => keep(page.url))
      if (content.file) await keep(content.file.url)
    }
  }
  sites[extension.id] = { listing, series: details, chapters, contents }
}

await Bun.write(
  resolve(out, "catalog.json"),
  JSON.stringify({
    recordedAt: new Date().toISOString(),
    server: version,
    user,
    contentRatings,
    libraries,
    series,
    seriesPublications,
    publications,
    pages,
    recent,
    extensions: installed,
    available,
    sites,
    files,
  }),
)
console.log(`kept ${Object.keys(files).length} files in ${out}`)
