import { createEffect, createSignal, on, onCleanup } from "solid-js"
import { useLocation, useNavigate, useRouter } from "@tanstack/solid-router"
import { Search } from "../components/icons.tsx"
import { Input } from "../components/ui/input.tsx"
import { keepRecentSearch } from "./searches.ts"

const searchPath = "/search"

/** What the shell's search fields show, shared so the sidebar's and the phone's agree. */
const [typed, setTyped] = createSignal("")

/**
 * The search field on every screen. Typing shows results in place of the
 * screen, Escape goes back to it, and / or ⌘K comes back to the field from
 * anywhere.
 */
export function SearchField(props: { class?: string }) {
  const navigate = useNavigate()
  const router = useRouter()
  const location = useLocation()
  const onResults = () => location().pathname === searchPath
  let input: HTMLInputElement | undefined

  // The field follows the address, so Back and Forward bring their search
  // with them, and leaving for a result empties it.
  createEffect(
    on(
      () => (onResults() ? ((location().search as { q?: string }).q ?? "") : ""),
      (q) => {
        if (q.trim() !== typed().trim()) setTyped(q)
      },
    ),
  )

  let timer: ReturnType<typeof setTimeout> | undefined
  let remember: ReturnType<typeof setTimeout> | undefined
  onCleanup(() => {
    clearTimeout(timer)
    clearTimeout(remember)
  })

  const run = (value: string) => {
    const q = value.trim()
    // Results open as a screen of their own, so Back returns to this one;
    // refining them after replaces it.
    if (!onResults() && !q) return
    void navigate({ to: searchPath, search: q ? { q } : {}, replace: onResults() })
    clearTimeout(remember)
    // A search counts as made once typing has rested a while.
    if (q) remember = setTimeout(() => keepRecentSearch(q), 1500)
  }
  const type = (value: string) => {
    setTyped(value)
    clearTimeout(timer)
    timer = setTimeout(() => run(value), 250)
  }
  const leave = () => {
    clearTimeout(timer)
    clearTimeout(remember)
    setTyped("")
    input?.blur()
    if (!onResults()) return
    if (router.history.canGoBack()) router.history.back()
    else void navigate({ to: "/" })
  }

  // / and ⌘K reach the field from anywhere but another field.
  const keydown = (event: KeyboardEvent) => {
    if (!input || input.offsetParent === null || event.defaultPrevented || event.altKey) return
    const target = event.target instanceof Element ? event.target : null
    const command = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
    const slash =
      event.key === "/" &&
      !event.metaKey &&
      !event.ctrlKey &&
      !target?.closest("input, textarea, select, [contenteditable], [role=dialog]")
    if (!command && !slash) return
    event.preventDefault()
    input.focus()
    input.select()
  }
  addEventListener("keydown", keydown)
  onCleanup(() => removeEventListener("keydown", keydown))

  return (
    <form
      role="search"
      class={props.class}
      onSubmit={(event) => {
        event.preventDefault()
        clearTimeout(timer)
        run(typed())
        if (typed().trim()) keepRecentSearch(typed().trim())
      }}
    >
      <label class="relative block [&>svg]:absolute [&>svg]:top-1/2 [&>svg]:left-3.5 [&>svg]:size-[18px] [&>svg]:-translate-y-1/2 [&>svg]:text-muted-foreground">
        <Search />
        <span class="sr-only">Search titles, series, people and publishers</span>
        <Input
          ref={(node) => (input = node)}
          type="search"
          class="h-10 ps-10"
          placeholder="Search"
          aria-keyshortcuts="/ Control+K Meta+K"
          enterkeyhint="search"
          value={typed()}
          onInput={(event) => type(event.currentTarget.value)}
          onKeyDown={(event) => {
            if (event.key !== "Escape") return
            // Escape clears the field first, as the browser's own does, then goes back.
            event.preventDefault()
            if (typed() && !onResults()) setTyped("")
            else leave()
          }}
        />
      </label>
    </form>
  )
}
