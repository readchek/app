import { For, Match, Show, Switch, createMemo, createSignal } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { useNavigate, useParams } from "@tanstack/solid-router"
import { AlertCircle, Search as SearchIcon } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { TextField, TextFieldInput, TextFieldLabel } from "../../components/ui/text-field.tsx"
import { accountKey } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
import { coverPath, librarySeries, search } from "../client.ts"
import { Cover } from "../Cover.tsx"
import { createPagedList } from "../paged.ts"
import { CoverGrid, GridItem, GridPlaceholder } from "../Shelf.tsx"
import { publicationTitle, seriesTitle, titleFromFileName } from "../titles.ts"
import { readableLibraries, routeAccount } from "./data.ts"

const pageSize = 60

/** A library's series in a grid, with a search of the library above them. */
export function Library() {
  const navigate = useNavigate()
  const params = useParams({ from: "/app/shared/$server/libraries/$libraryId" })
  const account = createMemo(() => {
    try {
      return routeAccount(params().server)
    } catch {
      return undefined
    }
  })
  const libraryId = () => Number(params().libraryId)
  const [library] = createResource(
    () => account(),
    async (current) => (await readableLibraries(current)).find((l) => l.id === libraryId()),
  )

  const [typed, setTyped] = createSignal("")
  const [query, setQuery] = createSignal("")
  let timer: ReturnType<typeof setTimeout> | undefined
  // Searching follows typing, a moment after it pauses.
  const type = (value: string) => {
    setTyped(value)
    clearTimeout(timer)
    timer = setTimeout(() => setQuery(value.trim()), 250)
  }

  const series = createPagedList(
    () => (account() && !query() ? { account: account()!, id: libraryId() } : undefined),
    (key, cursor, signal) =>
      librarySeries(key.account, key.id, { cursor, limit: pageSize }, signal),
  )
  const found = createPagedList(
    () => (account() && query() ? { account: account()!, id: libraryId(), q: query() } : undefined),
    (key, cursor, signal) =>
      search(key.account, { q: key.q, libraryId: key.id, cursor, limit: pageSize }, signal),
  )

  const name = () => library()?.name ?? ""

  return (
    <Screen
      title={name() || "Library"}
      back={<BackButton label="Shared" fallback={() => void navigate({ to: "/shared" })} />}
    >
      <Show
        when={account()}
        fallback={
          <Alert variant="destructive">
            <AlertCircle />
            <p>You're not signed in to this library's server. Add it in Settings.</p>
          </Alert>
        }
      >
        {(current) => (
          <>
            <TextField
              value={typed()}
              onChange={type}
              class="relative mb-8 block max-w-md [&>svg]:absolute [&>svg]:top-1/2 [&>svg]:left-3.5 [&>svg]:size-[18px] [&>svg]:-translate-y-1/2 [&>svg]:text-muted-foreground"
            >
              <SearchIcon />
              <TextFieldLabel class="sr-only">Search {name()}</TextFieldLabel>
              <TextFieldInput type="search" class="ps-10" placeholder={`Search ${name()}`} />
            </TextField>
            <Show
              when={query()}
              fallback={
                <Switch>
                  <Match when={series.state() === "failed"}>
                    <Failure error={series.error()} />
                  </Match>
                  <Match when={series.items().length === 0 && series.state() === "loading"}>
                    <GridPlaceholder />
                  </Match>
                  <Match when={series.items().length === 0}>
                    <p class="text-[15px] text-muted-foreground">
                      Nothing in this library yet. Its books show up once a scan finds them.
                    </p>
                  </Match>
                  <Match when={true}>
                    <CoverGrid>
                      <For each={series.items()}>
                        {(item) => {
                          const title = item.title.includes(" ")
                            ? item.title
                            : titleFromFileName(item.title)
                          return (
                            <GridItem
                              to={{ server: accountKey(current()), series: item.id }}
                              cover={
                                <Cover
                                  account={current()}
                                  path={
                                    item.coverPublicationId === null
                                      ? undefined
                                      : coverPath({ id: item.coverPublicationId })
                                  }
                                  title={title}
                                />
                              }
                              title={title}
                              detail={
                                item.publicationCount === 1
                                  ? "1 book"
                                  : `${item.publicationCount} books`
                              }
                            />
                          )
                        }}
                      </For>
                    </CoverGrid>
                    <div ref={series.sentinel} class="h-px" />
                  </Match>
                </Switch>
              }
            >
              <Switch>
                <Match when={found.state() === "failed"}>
                  <Failure error={found.error()} />
                </Match>
                <Match when={found.items().length === 0 && found.state() === "loading"}>
                  <GridPlaceholder count={6} />
                </Match>
                <Match when={found.items().length === 0}>
                  <p class="text-[15px] text-muted-foreground">
                    Nothing in {name()} matches “{query()}”.
                  </p>
                </Match>
                <Match when={true}>
                  <CoverGrid>
                    <For each={found.items()}>
                      {(publication) => (
                        <GridItem
                          to={{ server: accountKey(current()), read: publication.id }}
                          cover={
                            <Cover
                              account={current()}
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
            </Show>
          </>
        )}
      </Show>
    </Screen>
  )
}

export function Failure(props: { error: unknown }) {
  return (
    <Alert variant="destructive">
      <AlertCircle />
      <p>
        {props.error instanceof Error ? props.error.message : "Something went wrong. Try again."}
      </p>
    </Alert>
  )
}
