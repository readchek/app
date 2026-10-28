import { For, Show, createEffect, createMemo, createSignal, on, onCleanup } from "solid-js"
import { useNavigate } from "@tanstack/solid-router"
import { createResource } from "../lib/resource.ts"
import { cn } from "../lib/cn.ts"
import { BookOpen, Building, Gear, Globe, Search } from "../components/icons.tsx"
import {
  CommandDialog,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandLoading,
  Kbd,
} from "../components/ui/command.tsx"
import { type Account, accountKey, accounts, host } from "./accounts.ts"
import { coverPath, search } from "./client.ts"
import { Cover } from "./Cover.tsx"
import { clearRecentSearches, keepRecentSearch, recentSearches, siteDelay } from "./searches.ts"
import { installedExtensions, searchSite } from "./sites/api.ts"
import { publicationTitle, seriesTitle } from "./titles.ts"

// Search is a palette over whatever screen you're on, as in the iOS app's
// search sheet: ⌘K, Ctrl+K or / opens it from anywhere, Escape puts it away
// and leaves the screen as it was. It asks every server you're signed in to
// and the sites each one reaches. "Show all results" opens the full results
// screen, with its filters, for when a few top matches aren't enough.

const [open, setOpen] = createSignal(false)
const [typed, setTyped] = createSignal("")

/** Opens the palette, with `q` already typed when given. */
export function openSearch(q?: string) {
  if (q !== undefined) setTyped(q)
  setOpen(true)
}

const isMac = /Mac|iPhone|iPad/.test(navigator.platform)

/** What opens the palette, drawn as a search field in the sidebar or the phone's top bar. */
export function SearchButton(props: { class?: string }) {
  return (
    <button
      type="button"
      class={cn(
        "flex h-10 w-full items-center gap-2.5 rounded-xl border border-input bg-background px-3.5 text-start text-base text-muted-foreground/80 transition-[border-color,box-shadow] hover:border-ring/50 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/25 focus-visible:outline-none [&>svg]:size-[18px] [&>svg]:text-muted-foreground",
        props.class,
      )}
      aria-keyshortcuts="/ Control+K Meta+K"
      aria-haspopup="dialog"
      onClick={() => openSearch()}
    >
      <Search />
      <span class="flex-1">Search</span>
      <Kbd class="hidden lg:inline-flex">{isMac ? "⌘K" : "Ctrl K"}</Kbd>
    </button>
  )
}

const places = [
  { to: "/", label: "Reading Now", icon: BookOpen },
  { to: "/shared", label: "Shared", icon: Building },
  { to: "/sites", label: "Sites", icon: Globe },
  { to: "/settings", label: "Settings", icon: Gear },
] as const

/** How many matches each server and each site shows in the palette. */
const shown = 6

/** The palette itself, rendered once in the shell. */
export function SearchPalette() {
  const navigate = useNavigate()

  // ⌘K and Ctrl+K toggle it from anywhere; / opens it from anywhere but a field.
  const keydown = (event: KeyboardEvent) => {
    if (event.defaultPrevented || event.altKey) return
    const target = event.target instanceof Element ? event.target : null
    const command = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
    const slash =
      event.key === "/" &&
      !event.metaKey &&
      !event.ctrlKey &&
      !target?.closest("input, textarea, select, [contenteditable], [role=dialog]")
    if (!command && !slash) return
    event.preventDefault()
    setOpen((now) => (command ? !now : true))
  }
  addEventListener("keydown", keydown)
  onCleanup(() => removeEventListener("keydown", keydown))

  // Servers are asked once typing rests, and sites once it has rested a
  // while longer (see siteDelay).
  const [query, setQuery] = createSignal(typed().trim())
  const [siteQuery, setSiteQuery] = createSignal(typed().trim())
  let timer: ReturnType<typeof setTimeout> | undefined
  let siteTimer: ReturnType<typeof setTimeout> | undefined
  onCleanup(() => {
    clearTimeout(timer)
    clearTimeout(siteTimer)
  })
  createEffect(
    on(typed, (value) => {
      const q = value.trim()
      clearTimeout(timer)
      clearTimeout(siteTimer)
      timer = setTimeout(() => setQuery(q), q ? 250 : 0)
      siteTimer = setTimeout(() => setSiteQuery(q), q ? 250 + siteDelay : 0)
    }),
  )

  const signedIn = () => accounts().filter((account) => !account.expired)
  const many = () => signedIn().length > 1

  // Return opens the top match once there is one, unless you've moved to
  // another item yourself. Until matches arrive it shows all results.
  const [selected, setSelected] = createSignal("")
  let moved = false
  createEffect(
    on(query, () => {
      moved = false
      setSelected("")
    }),
  )
  const offer = (value: string) => {
    if (!moved && (selected() === "" || selected() === "all")) setSelected(value)
  }

  const go = (to: () => Promise<void> | void, remember = true) => {
    if (remember && query()) keepRecentSearch(query())
    setOpen(false)
    void to()
  }

  return (
    <CommandDialog
      title="Search"
      open={open()}
      onOpenChange={setOpen}
      commandProps={{
        shouldFilter: false,
        loop: true,
        label: "Search",
        value: selected(),
        onValueChange: setSelected,
        onKeyDown: (event) => {
          if (["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) moved = true
        },
        onPointerMove: () => (moved = true),
      }}
    >
      <CommandInput
        value={typed()}
        onValueChange={setTyped}
        placeholder="Search titles, series, people and sites"
        enterkeyhint="go"
      />
      <CommandList>
        <Show
          when={query()}
          fallback={
            <>
              <Show when={recentSearches().length > 0}>
                <CommandGroup heading="Recent searches">
                  <For each={recentSearches()}>
                    {(item) => (
                      <CommandItem value={`recent:${item}`} onSelect={() => setTyped(item)}>
                        <Search />
                        {item}
                      </CommandItem>
                    )}
                  </For>
                  <CommandItem
                    value="recent:clear"
                    class="text-muted-foreground"
                    onSelect={clearRecentSearches}
                  >
                    Clear recent searches
                  </CommandItem>
                </CommandGroup>
              </Show>
              <CommandGroup heading="Go to">
                <For each={places}>
                  {(place) => (
                    <CommandItem
                      value={`place:${place.to}`}
                      onSelect={() => go(() => navigate({ to: place.to }), false)}
                    >
                      <place.icon />
                      {place.label}
                    </CommandItem>
                  )}
                </For>
              </CommandGroup>
            </>
          }
        >
          <For each={signedIn()}>
            {(account) => (
              <LibraryMatches
                onFound={offer}
                account={account}
                query={query()}
                showHost={many()}
                onPick={(id) =>
                  go(() =>
                    navigate({
                      to: "/read/$server/$publicationId",
                      params: { server: accountKey(account), publicationId: String(id) },
                    }),
                  )
                }
              />
            )}
          </For>
          <For each={signedIn()}>
            {(account) => (
              <SiteMatches
                onFound={offer}
                account={account}
                query={siteQuery()}
                pending={siteQuery() !== query()}
                showHost={many()}
                onPick={(site, id) =>
                  go(() =>
                    navigate({
                      to: "/sites/$server/$extensionId/series",
                      params: { server: accountKey(account), extensionId: site },
                      search: { id },
                    }),
                  )
                }
              />
            )}
          </For>
          <CommandGroup>
            <CommandItem
              value="all"
              onSelect={() => go(() => navigate({ to: "/search", search: { q: query() } }))}
            >
              <Search />
              Show all results for “{query()}”
            </CommandItem>
          </CommandGroup>
        </Show>
      </CommandList>
    </CommandDialog>
  )
}

/** A match's small cover, title and where it's from. */
function Hit(props: { account: Account; cover?: string; title: string; detail?: string }) {
  return (
    <>
      <Cover
        account={props.account}
        path={props.cover}
        title={props.title}
        class="w-8 shrink-0 rounded-sm"
      />
      <span class="grid min-w-0">
        <span class="truncate">{props.title}</span>
        <Show when={props.detail}>
          <span class="truncate text-[13px] text-muted-foreground">{props.detail}</span>
        </Show>
      </span>
    </>
  )
}

function LibraryMatches(props: {
  account: Account
  query: string
  showHost: boolean
  onPick: (id: number) => void
  /** Called with the first match's item value when matches arrive. */
  onFound: (value: string) => void
}) {
  const [found] = createResource(
    () => ({ account: props.account, q: props.query }),
    async ({ account, q }) => ({ q, ...(await search(account, { q, limit: shown })) }),
  )
  createEffect(() => {
    const page = found.state === "ready" ? found() : undefined
    const first = page?.q === props.query ? page.items[0] : undefined
    if (first) props.onFound(`library:${accountKey(props.account)}:${first.id}`)
  })
  const heading = () =>
    props.showHost ? `Libraries on ${host(props.account.server)}` : "Libraries"

  return (
    <Show
      when={!found.loading || found.latest}
      fallback={<CommandLoading>Searching {heading().toLowerCase()}…</CommandLoading>}
    >
      <Show when={!found.error && found()?.items.length}>
        <CommandGroup heading={heading()}>
          <For each={found()!.items}>
            {(publication) => (
              <CommandItem
                value={`library:${accountKey(props.account)}:${publication.id}`}
                onSelect={() => props.onPick(publication.id)}
              >
                <Hit
                  account={props.account}
                  cover={publication.hasCover ? coverPath(publication) : undefined}
                  title={publicationTitle(publication)}
                  detail={seriesTitle(publication)}
                />
              </CommandItem>
            )}
          </For>
        </CommandGroup>
      </Show>
    </Show>
  )
}

function SiteMatches(props: {
  account: Account
  query: string
  /** Whether typing has moved on from `query` and the sites haven't been asked yet. */
  pending: boolean
  showHost: boolean
  onPick: (site: string, id: string) => void
  /** Called with the first match's item value when matches arrive. */
  onFound: (value: string) => void
}) {
  const [sites] = createResource(
    () => props.account,
    (account) => installedExtensions(account),
  )
  const usable = createMemo(() => (sites() ?? []).filter((site) => site.usable))

  return (
    <For each={usable()}>
      {(site) => {
        const [found] = createResource(
          // Nothing is asked while typing hasn't rested long enough.
          () => (!props.pending && props.query ? { q: props.query } : false),
          async ({ q }) => ({ q, ...(await searchSite(props.account, site.id, { q, page: 1 })) }),
        )
        createEffect(() => {
          const page = found.state === "ready" ? found() : undefined
          const first = page?.q === props.query ? page.items[0] : undefined
          if (first) props.onFound(`site:${accountKey(props.account)}:${site.id}:${first.id}`)
        })
        const heading = () =>
          props.showHost ? `${site.name} on ${host(props.account.server)}` : site.name
        return (
          <Show
            when={!props.pending && !found.loading}
            fallback={<CommandLoading>Searching {site.name}…</CommandLoading>}
          >
            <Show when={!found.error && found()?.items.length}>
              <CommandGroup heading={heading()}>
                <For each={found()!.items.slice(0, shown)}>
                  {(item) => (
                    <CommandItem
                      value={`site:${accountKey(props.account)}:${site.id}:${item.id}`}
                      onSelect={() => props.onPick(site.id, item.id)}
                    >
                      <Hit
                        account={props.account}
                        cover={item.coverUrl ?? undefined}
                        title={item.title}
                      />
                    </CommandItem>
                  )}
                </For>
              </CommandGroup>
            </Show>
          </Show>
        )
      }}
    </For>
  )
}
