import { For, Match, Show, Switch, createMemo, createSignal } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { useNavigate, useParams, useSearch } from "@tanstack/solid-router"
import { Search as SearchIcon } from "../../components/icons.tsx"
import { Input } from "../../components/ui/input.tsx"
import { accountKey } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
import { Cover } from "../Cover.tsx"
import { createPagedList } from "../paged.ts"
import { CoverGrid, GridItem, GridPlaceholder } from "../Shelf.tsx"
import { Failure } from "../shared/Library.tsx"
import { routeAccount } from "../shared/data.ts"
import { siteInfo, siteSeriesPage } from "./data.ts"
import { SiteFailure } from "./SiteFailure.tsx"

/** A site: the series it shows first, or the ones matching a search of it. */
export function Site() {
  const navigate = useNavigate()
  const params = useParams({ from: "/app/sites/$server/$extensionId" })
  const search = useSearch({ from: "/app/sites/$server/$extensionId" })
  const account = createMemo(() => {
    try {
      return routeAccount(params().server)
    } catch {
      return undefined
    }
  })
  const [info] = createResource(
    () => account() && { account: account()!, id: params().extensionId },
    ({ account, id }) => siteInfo(account, id),
  )

  const [typed, setTyped] = createSignal(search().q ?? "")
  const [query, setQuery] = createSignal((search().q ?? "").trim())
  let timer: ReturnType<typeof setTimeout> | undefined
  // A site is asked once typing pauses, a little longer than a library,
  // since each search reaches the site itself.
  const type = (value: string) => {
    setTyped(value)
    clearTimeout(timer)
    timer = setTimeout(() => {
      const trimmed = value.trim()
      setQuery(trimmed)
      void navigate({
        to: "/sites/$server/$extensionId",
        params: params(),
        search: trimmed ? { q: trimmed } : {},
        replace: true,
      })
    }, 400)
  }

  const series = createPagedList(
    () => account() && { account: account()!, id: params().extensionId, q: query() || undefined },
    (key, cursor, signal) => siteSeriesPage(key.account, key.id, key.q, cursor, signal),
  )

  const name = () => info()?.name ?? ""

  return (
    <Screen
      title={name() || (info.loading ? "" : "Site")}
      back={<BackButton label="Sites" fallback={() => void navigate({ to: "/sites" })} />}
    >
      <Show
        when={account()}
        fallback={
          <Failure
            error={new Error("You're not signed in to this site's server. Add it in Settings.")}
          />
        }
      >
        {(current) => (
          <>
            <label class="relative mb-8 block max-w-md [&>svg]:absolute [&>svg]:top-1/2 [&>svg]:left-3.5 [&>svg]:size-[18px] [&>svg]:-translate-y-1/2 [&>svg]:text-muted-foreground">
              <SearchIcon />
              <span class="sr-only">Search {name()}</span>
              <Input
                type="search"
                class="ps-10"
                placeholder={name() ? `Search ${name()}` : "Search"}
                value={typed()}
                onInput={(event) => type(event.currentTarget.value)}
              />
            </label>
            <Switch>
              <Match when={info.error}>
                <Failure error={info.error} />
              </Match>
              <Match when={series.state() === "failed" && series.items().length === 0}>
                <SiteFailure
                  account={current()}
                  site={info()}
                  error={series.error()}
                  retry={series.retry}
                />
              </Match>
              <Match when={series.items().length === 0 && series.state() === "loading"}>
                <GridPlaceholder />
              </Match>
              <Match when={series.items().length === 0}>
                <p class="text-[15px] text-muted-foreground">
                  {query()
                    ? `Nothing on ${name()} matches “${query()}”.`
                    : `${name()} has nothing to show yet. Search it for a series.`}
                </p>
              </Match>
              <Match when={true}>
                <CoverGrid>
                  <For each={series.items()}>
                    {(item) => (
                      <GridItem
                        to={{
                          server: accountKey(current()),
                          site: params().extensionId,
                          siteSeries: item.id,
                        }}
                        cover={
                          <Cover
                            account={current()}
                            path={item.coverUrl ?? undefined}
                            title={item.title}
                          />
                        }
                        title={item.title}
                      />
                    )}
                  </For>
                </CoverGrid>
                <Show when={series.state() === "failed"}>
                  <div class="mt-8">
                    <SiteFailure
                      account={current()}
                      site={info()}
                      error={series.error()}
                      retry={series.retry}
                    />
                  </div>
                </Show>
                <div ref={series.sentinel} class="h-px" />
              </Match>
            </Switch>
          </>
        )}
      </Show>
    </Screen>
  )
}
