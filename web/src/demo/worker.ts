// The demo's Worker at demo.chek.page: answers apps that talk to the demo
// as a server, such as the iOS app's Try the Demo, with answer.ts, and
// serves the demo build for everything else. The demo build itself never
// calls it, since it answers its own requests in the browser.

import { type Catalog, answer } from "./answer.ts"

type Env = { ASSETS: { fetch(request: Request): Promise<Response> } }

// The account is shared by every visitor, so like the server's demo users
// it keeps no reading positions.
const positions = { all: () => ({}), save: () => {} }

// Bearer tokens, never cookies, so any page may call the demo, as the web
// app at app.chek.page does with a server someone adds.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Range",
  "Access-Control-Expose-Headers": "Content-Range, Content-Length",
  "Access-Control-Max-Age": "86400",
}

let catalog: Promise<Catalog> | undefined

// Apps can read a book in parts, as from the server. Static assets answer
// with the whole file, so a single range is cut from it here.
async function ranged(response: Response, request: Request): Promise<Response> {
  const asked = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get("Range") ?? "")
  if (!asked || response.status !== 200) return response
  const bytes = await response.arrayBuffer()
  const size = bytes.byteLength
  const start = asked[1] ? Number(asked[1]) : Math.max(0, size - Number(asked[2]))
  const end = asked[1] && asked[2] ? Math.min(Number(asked[2]), size - 1) : size - 1
  if (start > end || start >= size) {
    return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${size}` } })
  }
  const headers = new Headers(response.headers)
  headers.set("Content-Range", `bytes ${start}-${end}/${size}`)
  headers.set("Content-Length", String(end - start + 1))
  return new Response(bytes.slice(start, end + 1), { status: 206, headers })
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    if (url.pathname !== "/health" && !url.pathname.startsWith("/api/")) {
      return env.ASSETS.fetch(request)
    }
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors })
    catalog ??= env.ASSETS.fetch(new Request(new URL("/demo-data/catalog.json", url)))
      .then((response) => response.json() as Promise<Catalog>)
      .catch((failure: unknown) => {
        // The next request tries again.
        catalog = undefined
        throw failure
      })
    const response = await answer(request, {
      catalog: await catalog,
      positions,
      file: async (name, original) =>
        ranged(
          await env.ASSETS.fetch(new Request(new URL(`/demo-data/files/${name}`, url))),
          original,
        ),
    })
    const answered = new Response(response.body, response)
    for (const [name, value] of Object.entries(cors)) answered.headers.set(name, value)
    return answered
  },
}
