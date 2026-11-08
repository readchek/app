import { For, type JSX, Match, Show, Switch, createMemo } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { Link, useParams } from "@tanstack/solid-router"
import { Info } from "../../components/icons.tsx"
import { buttonVariants } from "../../components/ui/button.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { cn } from "../../lib/cn.ts"
import { accountByKey, accountKey } from "../accounts.ts"
import { Breadcrumbs, type Crumb, Screen, row } from "../AppShell.tsx"
import {
  type PublicationSummary,
  comicFormats,
  continueReading,
  coverPath,
  series as getSeries,
  seriesPublications,
} from "../client.ts"
import { Cover } from "../Cover.tsx"
import { createPagedList } from "../paged.ts"
import { useTitle } from "../title.ts"
import { progressCaption, publicationTitle, titleFromFileName } from "../titles.ts"
import { readableLibraries } from "./data.ts"
import { Failure } from "./Library.tsx"

/** A series: its cover and title, the button that picks up where you are, and its books. */
export function Series() {
  const params = useParams({ from: "/app/shared/$server/series/$seriesId" })
  const account = createMemo(() => {
    const found = accountByKey(params().server)
    return found && !found.expired ? found : undefined
  })
  const seriesId = () => Number(params().seriesId)

  const [info] = createResource(
    () => account() && { account: account()!, id: seriesId() },
    ({ account, id }) => getSeries(account, id),
  )
  const books = createPagedList(
    () => account() && { account: account()!, id: seriesId() },
    (key, cursor, signal) =>
      seriesPublications(key.account, key.id, { cursor, limit: 100 }, signal),
    (key) => `series:${accountKey(key.account)}:${key.id}`,
  )
  // The library the series is in, for the way back to it.
  const [library] = createResource(
    () => account() && info() && { account: account()!, id: info()!.libraryId },
    async ({ account, id }) => (await readableLibraries(account)).find((l) => l.id === id),
  )
  // Where you are in the series, from what you're reading on the server.
  const [reading] = createResource(
    () => account(),
    async (current) => {
      const page = await continueReading(current, { limit: 200 })
      return page.items.filter((item) => item.publication.series.id === seriesId())
    },
  )

  const title = () => {
    const raw = info()?.title ?? ""
    return raw.includes(" ") ? raw : titleFromFileName(raw)
  }
  const progressOf = (publication: PublicationSummary) =>
    reading()?.find((item) => item.publication.id === publication.id)?.progress
  const nextUp = () => reading()?.[0]?.publication ?? books.items()[0]
  useTitle(title)

  const trail = (): Crumb[] => {
    const found = library()
    return [
      { label: "Shared", to: { to: "/shared" } },
      ...(found && account()
        ? [
            {
              label: found.name,
              to: {
                to: "/shared/$server/libraries/$libraryId",
                params: { server: accountKey(account()!), libraryId: String(found.id) },
              },
            } satisfies Crumb,
          ]
        : []),
    ]
  }

  return (
    <Screen title="" back={<Breadcrumbs trail={trail()} />} detail>
      <Switch>
        <Match when={!account()}>
          <Failure
            error={new Error("You're not signed in to this series' server. Add it in Settings.")}
          />
        </Match>
        <Match when={info.error}>
          <Failure error={info.error} />
        </Match>
        <Match when={info()}>
          {(found) => (
            <Detail
              cover={
                <Cover
                  account={account()!}
                  path={
                    found().coverPublicationId === null
                      ? undefined
                      : coverPath({ id: found().coverPublicationId! })
                  }
                  title={title()}
                />
              }
              heading={
                <>
                  <h1 class="text-[30px] leading-[1.05] tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
                    {title()}
                  </h1>
                  <p class="mt-2 text-[15px] text-muted-foreground">
                    {found().publicationCount === 1
                      ? "1 book"
                      : `${found().publicationCount} books`}
                  </p>
                </>
              }
              actions={
                <Show when={nextUp()}>
                  {(next) => (
                    <Link
                      to="/read/$server/$publicationId"
                      params={{ server: accountKey(account()!), publicationId: String(next().id) }}
                      class={buttonVariants({ class: "w-full sm:w-auto sm:px-8" })}
                    >
                      {reading()?.length ? `Continue ${publicationTitle(next())}` : "Start Reading"}
                    </Link>
                  )}
                </Show>
              }
            >
              <Show when={account()}>
                {(current) => (
                  <Switch>
                    <Match when={books.state() === "failed"}>
                      <Failure error={books.error()} />
                    </Match>
                    <Match when={true}>
                      <ul class="divide-y border-y">
                        <For each={books.items()}>
                          {(book) => (
                            <li class="flex items-center gap-2">
                              <Link
                                to="/read/$server/$publicationId"
                                params={{
                                  server: accountKey(current()),
                                  publicationId: String(book.id),
                                }}
                                class={cn(row, "group min-w-0 flex-1 py-3 lg:py-2.5")}
                              >
                                <div class="w-12 shrink-0 lg:w-10">
                                  <Cover
                                    account={current()}
                                    path={book.hasCover ? coverPath(book) : undefined}
                                    title=""
                                    class="rounded-sm"
                                  />
                                </div>
                                <span class="grid min-w-0 gap-0.5">
                                  <span class="truncate text-[17px] lg:text-[15px]">
                                    {publicationTitle(book)}
                                  </span>
                                  <span class="truncate text-sm text-muted-foreground lg:text-[13px]">
                                    {bookDetail(book, progressCaption(progressOf(book)))}
                                  </span>
                                </span>
                              </Link>
                              <Link
                                to="/shared/$server/books/$publicationId"
                                params={{
                                  server: accountKey(current()),
                                  publicationId: String(book.id),
                                }}
                                aria-label={`About ${publicationTitle(book)}`}
                                title="About this book"
                                class={cn(
                                  buttonVariants({ variant: "ghost", size: "sm" }),
                                  "size-10 shrink-0 px-0 text-muted-foreground [&_svg]:size-5",
                                )}
                              >
                                <Info />
                              </Link>
                            </li>
                          )}
                        </For>
                      </ul>
                      <Show when={books.state() === "loading"}>
                        <div class="divide-y" aria-hidden="true">
                          <For each={[0, 1, 2]}>
                            {() => (
                              <div class="flex items-center gap-3.5 py-3">
                                <Skeleton class="aspect-[2/3] w-12 rounded-sm" />
                                <div class="grid gap-2">
                                  <Skeleton class="h-4 w-40" />
                                  <Skeleton class="h-3 w-20" />
                                </div>
                              </div>
                            )}
                          </For>
                        </div>
                      </Show>
                      <div ref={books.sentinel} class="h-px" />
                    </Match>
                  </Switch>
                )}
              </Show>
            </Detail>
          )}
        </Match>
        <Match when={true}>
          <DetailPlaceholder />
        </Match>
      </Switch>
    </Screen>
  )
}

/**
 * One thing and its list: a series and its books, a book and its details,
 * a site's series and its chapters. On a phone the cover sits beside the
 * title with everything else below, as in the iOS app. On a wide window
 * the cover stays put at the side while the list scrolls, as a website's
 * detail page does.
 */
export function Detail(props: {
  cover: JSX.Element
  heading: JSX.Element
  actions?: JSX.Element
  /** Shown under the heading on every width, such as a description. */
  about?: JSX.Element
  children?: JSX.Element
}) {
  return (
    <div class="grid grid-cols-[8rem_minmax(0,1fr)] items-end gap-x-5 sm:grid-cols-[10rem_minmax(0,1fr)] sm:gap-x-7 lg:grid-cols-[13rem_minmax(0,1fr)] lg:items-start lg:gap-x-10">
      <div class="lg:sticky lg:top-10 lg:row-span-4 lg:self-start">{props.cover}</div>
      <div class="min-w-0 pb-1 lg:pt-1">{props.heading}</div>
      <Show when={props.actions}>
        <div class="col-span-2 mt-6 flex flex-col gap-3 sm:flex-row lg:col-span-1 lg:col-start-2 lg:mt-5">
          {props.actions}
        </div>
      </Show>
      <Show when={props.about}>
        <div class="col-span-2 lg:col-span-1 lg:col-start-2">{props.about}</div>
      </Show>
      <Show when={props.children}>
        <div class="col-span-2 mt-8 lg:col-span-1 lg:col-start-2">{props.children}</div>
      </Show>
    </div>
  )
}

/** A `Detail` the shape of one that's loading. */
export function DetailPlaceholder() {
  return (
    <div
      class="grid grid-cols-[8rem_minmax(0,1fr)] items-end gap-x-5 sm:grid-cols-[10rem_minmax(0,1fr)] sm:gap-x-7 lg:grid-cols-[13rem_minmax(0,1fr)] lg:items-start lg:gap-x-10"
      aria-hidden="true"
    >
      <Skeleton class="aspect-[2/3] w-full rounded-md" />
      <div class="grid gap-3 pb-1 lg:pt-1">
        <Skeleton class="h-8 w-48" />
        <Skeleton class="h-4 w-20" />
      </div>
    </div>
  )
}

const formatNames: Record<string, string> = {
  epub: "EPUB",
  pdf: "PDF",
  mobi: "MOBI",
  azw3: "Kindle",
  fb2: "FictionBook",
  txt: "Text",
  markdown: "Markdown",
}

/** "200 pages", or the format for books without pages, then where you are. */
export function bookDetail(book: PublicationSummary, status?: string): string {
  const kind =
    comicFormats.includes(book.format) && book.pageCount
      ? `${book.pageCount} pages`
      : (formatNames[book.format] ?? "")
  return [kind, status, book.available ? undefined : "Missing"].filter(Boolean).join(" · ")
}
