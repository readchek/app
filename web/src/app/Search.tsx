import { For, Match, Show, Switch, createMemo, createResource, createSignal } from "solid-js"
import { useNavigate, useSearch } from "@tanstack/solid-router"
import { Search as SearchIcon } from "../components/icons.tsx"
import { Button } from "../components/ui/button.tsx"
import { Input } from "../components/ui/input.tsx"
import { Select } from "../components/ui/select.tsx"
import { ToggleGroup } from "../components/ui/toggle-group.tsx"
import { type Account, accountKey, accounts, host } from "./accounts.ts"
import { Screen } from "./AppShell.tsx"
import { type PublicationSummary, comicFormats, coverPath, search } from "./client.ts"
import { Cover } from "./Cover.tsx"
import { createPagedList } from "./paged.ts"
import { CoverGrid, GridItem, GridPlaceholder } from "./Shelf.tsx"
import { Failure } from "./shared/Library.tsx"
import { readableLibraries } from "./shared/data.ts"
import { publicationTitle, seriesTitle } from "./titles.ts"

type Kind = "all" | "comics" | "books"
type Place = { value: string; label: string; server?: string; libraryId?: number }

const recentKey = "chek.recentSearches"
const recentCount = 8

function storedRecent(): string[] {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(recentKey) ?? "[]")
    return Array.isArray(value)
      ? value.filter((item): item is string => typeof item === "string")
      : []
  } catch {
    return []
  }
}

/** Search: every server you're signed in to at once, or one place, as the iOS app's Search. */
export function Search() {
  const navigate = useNavigate()
  const params = useSearch({ from: "/app/search" })
  const [typed, setTyped] = createSignal(params().q ?? "")
  const [query, setQuery] = createSignal((params().q ?? "").trim())
  const [kind, setKind] = createSignal<Kind>("all")
  const [placeValue, setPlaceValue] = createSignal("everywhere")
  const [recent, setRecent] = createSignal(storedRecent())

  const signedIn = () => accounts().filter((a) => !a.expired)
  const [libraries] = createResource(
    () => signedIn(),
    async (list) =>
      (
        await Promise.allSettled(
          list.map(async (account) =>
            (await readableLibraries(account)).map((library) => ({ account, library })),
          ),
        )
      ).flatMap((result) => (result.status === "fulfilled" ? result.value : [])),
  )

  const places = createMemo<Place[]>(() => {
    const many = signedIn().length > 1
    return [
      { value: "everywhere", label: "Everywhere" },
      ...(many
        ? signedIn().map((account) => ({
            value: accountKey(account),
            label: host(account.server),
            server: accountKey(account),
          }))
        : []),
      ...(libraries() ?? []).map(({ account, library }) => ({
        value: `${accountKey(account)}/${library.id}`,
        label: many ? `${library.name} on ${host(account.server)}` : library.name,
        server: accountKey(account),
        libraryId: library.id,
      })),
    ]
  })
  const place = () => places().find((p) => p.value === placeValue()) ?? places()[0]!
  const targets = () =>
    signedIn().filter((account) => !place().server || accountKey(account) === place().server)

  let timer: ReturnType<typeof setTimeout> | undefined
  let remember: ReturnType<typeof setTimeout> | undefined
  const run = (value: string) => {
    const trimmed = value.trim()
    setQuery(trimmed)
    void navigate({ to: "/search", search: trimmed ? { q: trimmed } : {}, replace: true })
    clearTimeout(remember)
    // A search counts as made once typing has rested a while.
    if (trimmed) remember = setTimeout(() => keepRecent(trimmed), 1500)
  }
  const type = (value: string) => {
    setTyped(value)
    clearTimeout(timer)
    timer = setTimeout(() => run(value), 250)
  }
  const keepRecent = (value: string) => {
    const next = [value, ...recent().filter((item) => item !== value)].slice(0, recentCount)
    try {
      localStorage.setItem(recentKey, JSON.stringify(next))
    } catch {
      // Recent searches are only a convenience.
    }
    setRecent(next)
  }
  const clearRecent = () => {
    try {
      localStorage.removeItem(recentKey)
    } catch {
      // Nothing was stored.
    }
    setRecent([])
  }

  return (
    <Screen title="Search">
      <form
        class="grid max-w-2xl gap-4"
        onSubmit={(event) => {
          event.preventDefault()
          clearTimeout(timer)
          run(typed())
          if (typed().trim()) keepRecent(typed().trim())
        }}
      >
        <label class="relative block [&>svg]:absolute [&>svg]:top-1/2 [&>svg]:left-3.5 [&>svg]:size-[18px] [&>svg]:-translate-y-1/2 [&>svg]:text-muted-foreground">
          <SearchIcon />
          <span class="sr-only">Search titles, series, people and publishers</span>
          <Input
            type="search"
            class="ps-10"
            placeholder="Titles, series, people and publishers"
            value={typed()}
            onInput={(event) => type(event.currentTarget.value)}
            autofocus
          />
        </label>
        <div class="flex flex-wrap items-end gap-3">
          <Select
            label="Where"
            class="min-w-44"
            options={places()}
            value={place()}
            onChange={(chosen) => setPlaceValue(chosen.value)}
          />
          <ToggleGroup
            label="Kind"
            class="w-64 [&>span]:sr-only"
            value={kind()}
            options={[
              { value: "all", label: "All" },
              { value: "comics", label: "Comics" },
              { value: "books", label: "Books" },
            ]}
            onChange={setKind}
          />
        </div>
      </form>

      <div class="mt-10">
        <Show
          when={query()}
          fallback={
            <Show when={recent().length > 0}>
              <section class="max-w-2xl">
                <div class="mb-2 flex items-center justify-between">
                  <h2 class="text-[22px] leading-tight tracking-[-0.03em]">Recent searches</h2>
                  <Button variant="ghost" size="sm" onClick={clearRecent}>
                    Clear
                  </Button>
                </div>
                <ul class="divide-y border-y">
                  <For each={recent()}>
                    {(item) => (
                      <li>
                        <button
                          type="button"
                          class="flex w-full items-center gap-3 py-3 text-start text-[17px] text-link hover:underline focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none [&>svg]:size-[18px] [&>svg]:text-muted-foreground"
                          onClick={() => {
                            setTyped(item)
                            run(item)
                          }}
                        >
                          <SearchIcon />
                          {item}
                        </button>
                      </li>
                    )}
                  </For>
                </ul>
              </section>
            </Show>
          }
        >
          <For each={targets()}>
            {(account) => (
              <Results
                account={account}
                query={query()}
                libraryId={place().libraryId}
                kind={kind()}
                showHost={targets().length > 1}
              />
            )}
          </For>
        </Show>
      </div>
    </Screen>
  )
}

function matchesKind(publication: PublicationSummary, kind: Kind): boolean {
  if (kind === "all") return true
  return comicFormats.includes(publication.format) === (kind === "comics")
}

function Results(props: {
  account: Account
  query: string
  libraryId?: number
  kind: Kind
  showHost: boolean
}) {
  const found = createPagedList(
    () => ({ account: props.account, q: props.query, libraryId: props.libraryId }),
    (key, cursor, signal) =>
      search(key.account, { q: key.q, libraryId: key.libraryId, cursor, limit: 60 }, signal),
  )
  const shown = () => found.items().filter((item) => matchesKind(item, props.kind))

  return (
    <section class="mb-10">
      <Show when={props.showHost}>
        <h2 class="mb-4 text-[22px] leading-tight tracking-[-0.03em]">
          {host(props.account.server)}
        </h2>
      </Show>
      <Switch>
        <Match when={found.state() === "failed"}>
          <Failure error={found.error()} />
        </Match>
        <Match when={shown().length === 0 && found.state() === "loading"}>
          <GridPlaceholder count={6} />
        </Match>
        <Match when={shown().length === 0 && found.state() === "done"}>
          <p class="text-[15px] text-muted-foreground">Nothing matches “{props.query}”.</p>
        </Match>
        <Match when={true}>
          <CoverGrid>
            <For each={shown()}>
              {(publication) => (
                <GridItem
                  to={{ server: accountKey(props.account), read: publication.id }}
                  cover={
                    <Cover
                      account={props.account}
                      path={publication.hasCover ? coverPath(publication) : undefined}
                      title={publicationTitle(publication)}
                    />
                  }
                  title={publicationTitle(publication)}
                  detail={seriesTitle(publication)}
                />
              )}
            </For>
          </CoverGrid>
          <div ref={found.sentinel} class="h-px" />
        </Match>
      </Switch>
    </section>
  )
}
