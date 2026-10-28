// The demo build's server, run in the browser: answers the app's requests
// to this page's own address with answer.ts, before they reach the
// network. Reading positions are kept in this browser, so every visitor
// has a demo of their own.

import type { Progress } from "../app/client.ts"
import { type Backend, type Catalog, answer } from "./answer.ts"

const passthrough = window.fetch.bind(window)

const key = "chek.demo.progress"

function saved(): Record<string, Progress> {
  try {
    return JSON.parse(localStorage.getItem(key) ?? "{}") as Record<string, Progress>
  } catch {
    return {}
  }
}

/** Answers the app's requests to this page's own address from the demo's snapshot. */
export function start() {
  const backend: Promise<Backend> = passthrough("/demo-data/catalog.json").then(
    async (response) => {
      if (!response.ok) throw new Error(`The demo's library answered ${response.status}.`)
      return {
        catalog: (await response.json()) as Catalog,
        positions: {
          all: saved,
          save(id, progress) {
            try {
              localStorage.setItem(key, JSON.stringify({ ...saved(), [id]: progress }))
            } catch {
              // Private browsing can refuse storage; the position lasts until reload.
            }
          },
        },
        file: (name) => passthrough(`/demo-data/files/${name}`),
      }
    },
  )
  window.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init)
    const url = new URL(request.url)
    if (url.origin !== location.origin || !url.pathname.startsWith("/api/v1/")) {
      return passthrough(input, init)
    }
    request.signal.throwIfAborted()
    return answer(request, await backend)
  }) as typeof fetch
}
