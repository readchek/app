import { For, Match, Show, Switch, createMemo, createSignal } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { Link, useNavigate, useSearch } from "@tanstack/solid-router"
import { Search as SearchIcon } from "../components/icons.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "../components/ui/select.tsx"
import { ToggleGroup } from "../components/ui/toggle-group.tsx"
import { type Account, accountKey, accounts, host } from "./accounts.ts"
import { Screen } from "./AppShell.tsx"
import { type PublicationSummary, comicFormats, coverPath, search } from "./client.ts"
import { Cover } from "./Cover.tsx"
import { createPagedList } from "./paged.ts"
import {
  CoverGrid,
  GridItem,
  GridPlaceholder,
  Shelf,
  ShelfItem,
  ShelfPlaceholder,
} from "./Shelf.tsx"
import { Failure } from "./shared/Library.tsx"
import { clearRecentSearches, keepRecentSearch, recentSearches } from "./searches.ts"
import { openSearch } from "./SearchPalette.tsx"
import { readableLibraries } from "./shared/data.ts"
import { type InstalledExtension, installedExtensions, searchSite } from "./sites/api.ts"
import { publicationTitle, seriesTitle } from "./titles.ts"

type Kind = "all" | "comics" | "books"
type Place = { value: string; label: string; server?: string; libraryId?: number }

/**
 * All the results of a search, as the iOS app's Search: every server you're
 * signed in to at once, or one place. The palette shows the top few; this
 * screen opens from its "Show all results".
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

  // This screen opens on purpose, from the palette's "Show all results", so
  // sites are asked at once rather than after typing rests.
  const searchFor = (item: string) => {
    keepRecentSearch(item)
    void navigate({ to: "/search", search: { q: item }, replace: true })
  }

  return (
    <Screen
      title={query() ? `Results for “${query()}”` : "Search"}
      actions={
        <Button variant="outline" size="sm" onClick={() => openSearch(query())}>
          <SearchIcon />
          Search again
        </Button>
      }
    >
      <div class="flex flex-wrap items-end gap-3">
        <Select<Place>
          class="min-w-44"
          options={places()}
          optionValue="value"
          optionTextValue="label"
          value={place()}
          onChange={(chosen) => chosen && setPlaceValue(chosen.value)}
          disallowEmptySelection
          gutter={6}
          itemComponent={(item) => (
            <SelectItem item={item.item}>{item.item.rawValue.label}</SelectItem>
          )}
        >
          <SelectLabel class="sr-only">Where</SelectLabel>
          <SelectTrigger>
            <SelectValue<Place>>{(state) => state.selectedOption().label}</SelectValue>
          </SelectTrigger>
          <SelectContent />
        </Select>
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
          {/* Sites are searched too, as on iOS, unless the search is of one library. */}
          <Show when={place().libraryId === undefined}>
            <For each={targets()}>
              {(account) => (
                <SiteResults
                  account={account}
                  query={query()}
                  kind={kind()}
                  showHost={targets().length > 1}
                />
              )}
            </For>
          </Show>
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
          <p class="text-[15px] text-muted-foreground">
            Nothing in your libraries matches “{props.query}”.
          </p>
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

/** Whether a site has the kind of thing asked for: comics come as pages or PDFs, books as EPUB. */
function siteMatchesKind(site: InstalledExtension, kind: Kind): boolean {
  if (kind === "all") return true
  return site.formats.some((format) => (format === "epub") === (kind === "books"))
}

/** The sites a server reaches, each searched for the first page of its matches. */
function SiteResults(props: { account: Account; query: string; kind: Kind; showHost: boolean }) {
  const [sites] = createResource(
    () => props.account,
    (account) => installedExtensions(account),
  )
  const shown = () =>
    (sites() ?? []).filter((site) => site.usable && siteMatchesKind(site, props.kind))

  return (
    <Show when={shown().length > 0}>
      <section class="mb-10">
        <Show when={props.showHost}>
          <h2 class="mb-6 text-[22px] leading-tight tracking-[-0.03em]">
            Sites on {host(props.account.server)}
          </h2>
        </Show>
        <For each={shown()}>
          {(site) => <SiteShelf account={props.account} site={site} query={props.query} />}
        </For>
      </section>
    </Show>
  )
}

function SiteShelf(props: { account: Account; site: InstalledExtension; query: string }) {
  const [found] = createResource(
    () => ({ account: props.account, id: props.site.id, q: props.query }),
    ({ account, id, q }) => searchSite(account, id, { q, page: 1 }),
  )
  const seeAll = () => (
    <Link
      to="/sites/$server/$extensionId"
      params={{ server: accountKey(props.account), extensionId: props.site.id }}
      search={{ q: props.query }}
      class={buttonVariants({ variant: "link", size: "inline" })}
    >
      {found.error ? `Open ${props.site.name}` : "See all"}
    </Link>
  )

  return (
    <Switch>
      <Match when={found.error}>
        {/* A site can need a sign-in or a check first, which its own page offers. */}
        <Shelf title={props.site.name} action={seeAll()}>
          <li class="text-[15px] text-muted-foreground">
            {props.site.name} couldn't be searched right now.
          </li>
        </Shelf>
      </Match>
      <Match when={found.loading}>
        <ShelfPlaceholder />
      </Match>
      <Match when={found()?.items.length === 0}>
        <Shelf title={props.site.name}>
          <li class="text-[15px] text-muted-foreground">
            Nothing on {props.site.name} matches “{props.query}”.
          </li>
        </Shelf>
      </Match>
      <Match when={found()}>
        {(page) => (
          <Shelf title={props.site.name} action={seeAll()}>
            <For each={page().items}>
              {(item) => (
                <ShelfItem
                  to={{
                    server: accountKey(props.account),
                    site: props.site.id,
                    siteSeries: item.id,
                  }}
                  cover={
                    <Cover
                      account={props.account}
                      path={item.coverUrl ?? undefined}
                      title={item.title}
                    />
                  }
                  title={item.title}
                />
              )}
            </For>
          </Shelf>
        )}
      </Match>
    </Switch>
  )
}
