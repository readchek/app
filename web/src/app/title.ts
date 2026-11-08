import { createEffect, onCleanup } from "solid-js"

const appName = "Chek"

// How many screens are asking for a title at once. The reader opens over a
// screen that's still mounted for a moment, so the newest ask wins, and the
// tab goes back to the app's name only once no screen asks for one.
let asks = 0

/**
 * Puts `title` in the browser tab, as a website does, so history, bookmarks
 * and the tab strip say which screen this is. An empty title leaves the tab
 * as it was, for screens that set theirs once they've loaded.
 */
export function useTitle(title: () => string | undefined) {
  asks += 1
  createEffect(() => {
    const current = title()?.trim()
    if (current) document.title = `${current} · ${appName}`
  })
  onCleanup(() => {
    asks -= 1
    if (asks === 0) document.title = appName
  })
}
