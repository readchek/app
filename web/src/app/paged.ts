import { createEffect, createSignal, on, onCleanup } from "solid-js"
import type { Page } from "./client.ts"

export type PagedState = "loading" | "idle" | "done" | "failed"

/**
 * A list the server sends a page at a time, loaded further as its end
 * comes near the screen. At most one page is asked for at a time, and a
 * change of `key`, such as a new search, drops what was loaded and starts
 * again, ignoring answers still on their way.
 */
export function createPagedList<T, K>(
  key: () => K | undefined,
  fetchPage: (key: K, cursor: string | undefined, signal: AbortSignal) => Promise<Page<T>>,
) {
  const [items, setItems] = createSignal<T[]>([])
  const [state, setState] = createSignal<PagedState>("loading")
  const [error, setError] = createSignal<unknown>()
  let cursor: string | undefined
  let controller: AbortController | undefined
  let end: HTMLElement | undefined

  // The observer only says when the end crosses into view, so a page too
  // short to push it back out is followed by the next one at once.
  const endInView = () => {
    if (!end?.isConnected) return false
    return end.getBoundingClientRect().top < innerHeight + 600
  }

  const more = async () => {
    const current = key()
    if (current === undefined || controller) return
    const mine = new AbortController()
    controller = mine
    setState("loading")
    try {
      const page = await fetchPage(current, cursor, mine.signal)
      if (mine.signal.aborted) return
      setItems((before) => [...before, ...page.items])
      cursor = page.nextCursor
      setState(cursor ? "idle" : "done")
      if (cursor) requestAnimationFrame(() => endInView() && state() === "idle" && void more())
    } catch (failure) {
      if (mine.signal.aborted) return
      setError(failure)
      setState("failed")
    } finally {
      if (controller === mine) controller = undefined
    }
  }

  createEffect(
    on(key, (current) => {
      controller?.abort()
      controller = undefined
      cursor = undefined
      setItems([])
      setError(undefined)
      if (current === undefined) setState("done")
      else void more()
    }),
  )
  onCleanup(() => controller?.abort())

  /** Put on an element at the end of the list: it loads the next page when it nears the screen. */
  const sentinel = (element: HTMLElement) => {
    end = element
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting) && state() === "idle") void more()
      },
      { rootMargin: "600px" },
    )
    observer.observe(element)
    onCleanup(() => observer.disconnect())
  }

  /** Asks again for the page that failed. */
  const retry = () => {
    if (state() !== "failed") return
    setError(undefined)
    void more()
  }

  return { items, state, error, more, retry, sentinel }
}
