import { For, Match, Show, Switch, createMemo, createResource, createSignal } from "solid-js"
import { useNavigate, useSearch } from "@tanstack/solid-router"
import { Search as SearchIcon } from "../components/icons.tsx"
import { Button } from "../components/ui/button.tsx"
import { Select } from "../components/ui/select.tsx"
import { ToggleGroup } from "../components/ui/toggle-group.tsx"
import { type Account, accountKey, accounts, host } from "./accounts.ts"
import { Screen } from "./AppShell.tsx"
import { type PublicationSummary, comicFormats, coverPath, search } from "./client.ts"
import { Cover } from "./Cover.tsx"
import { createPagedList } from "./paged.ts"
import { CoverGrid, GridItem, GridPlaceholder } from "./Shelf.tsx"
import { Failure } from "./shared/Library.tsx"
import { clearRecentSearches, keepRecentSearch, recentSearches } from "./searches.ts"
import { readableLibraries } from "./shared/data.ts"
import { publicationTitle, seriesTitle } from "./titles.ts"

type Kind = "all" | "comics" | "books"
type Place = { value: string; label: string; server?: string; libraryId?: number }

/**
 * Search results, as the iOS app's Search: every server you're signed in
 * to at once, or one place. The search field is the shell's, on every screen.
 */
export function Search() {
  const navigate = useNavigate()
  const params = useSearch({ from: "/app/search" })
  const query = () => (params().q ?? "").trim()
  const [kind, setKind] = createSignal<Kind>("all")
  const [placeValue, setPlaceValue] = createSignal("everywhere")

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

  const searchFor = (item: string) => {
    keepRecentSearch(item)
    void navigate({ to: "/search", search: { q: item }, replace: true })
  }

  return (
    <Screen title={query() ? `Results for “${query()}”` : "Search"}>
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

      <div class="mt-10">
        <Show
          when={query()}
          fallback={
            <Show
              when={recentSearches().length > 0}
              fallback={
                <p class="text-[15px] text-muted-foreground">
                  Search for titles, series, people and publishers on every server you use.
                </p>
              }
            >
              <section class="max-w-2xl">
                <div class="mb-2 flex items-center justify-between">
                  <h2 class="text-[22px] leading-tight tracking-[-0.03em]">Recent searches</h2>
                  <Button variant="ghost" size="sm" onClick={clearRecentSearches}>
                    Clear
                  </Button>
                </div>
                <ul class="divide-y border-y">
                  <For each={recentSearches()}>
                    {(item) => (
                      <li>
                        <button
                          type="button"
                          class="flex w-full items-center gap-3 py-3 text-start text-[17px] text-link hover:underline focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none [&>svg]:size-[18px] [&>svg]:text-muted-foreground"
                          onClick={() => searchFor(item)}
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
