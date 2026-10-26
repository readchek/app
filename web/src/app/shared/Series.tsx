import { For, Match, Show, Switch, createMemo, createResource } from "solid-js"
import { Link, useNavigate, useParams } from "@tanstack/solid-router"
import { Info } from "../../components/icons.tsx"
import { buttonVariants } from "../../components/ui/button.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { cn } from "../../lib/cn.ts"
import { accountByKey, accountKey } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
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
import { progressCaption, publicationTitle, titleFromFileName } from "../titles.ts"
import { Failure } from "./Library.tsx"

/** A series: its cover and title, the button that picks up where you are, and its books. */
export function Series() {
  const navigate = useNavigate()
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

  return (
    <Screen
      title=""
      back={<BackButton label="Back" fallback={() => void navigate({ to: "/shared" })} />}
      narrow
    >
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
            <>
              <div class="flex items-end gap-5 sm:gap-7">
                <div class="w-32 shrink-0 sm:w-40">
                  <Cover
                    account={account()!}
                    path={
                      found().coverPublicationId === null
                        ? undefined
                        : coverPath({ id: found().coverPublicationId! })
                    }
                    title={title()}
                  />
                </div>
                <div class="min-w-0 pb-1">
                  <h1 class="text-[30px] leading-[1.05] tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
                    {title()}
                  </h1>
                  <p class="mt-2 text-[15px] text-muted-foreground">
                    {found().publicationCount === 1
                      ? "1 book"
                      : `${found().publicationCount} books`}
                  </p>
                </div>
              </div>
              <Show when={nextUp()}>
                {(next) => (
                  <Link
                    to="/read/$server/$publicationId"
                    params={{ server: accountKey(account()!), publicationId: String(next().id) }}
                    class={buttonVariants({ class: "mt-6 w-full sm:w-auto sm:px-8" })}
                  >
                    {reading()?.length ? `Continue ${publicationTitle(next())}` : "Start Reading"}
                  </Link>
                )}
              </Show>
            </>
          )}
        </Match>
        <Match when={true}>
          <div class="flex items-end gap-5" aria-hidden="true">
            <Skeleton class="aspect-[2/3] w-32 rounded-md sm:w-40" />
            <div class="grid gap-3 pb-1">
              <Skeleton class="h-8 w-48" />
              <Skeleton class="h-4 w-20" />
            </div>
          </div>
        </Match>
      </Switch>

      <Show when={account()}>
        {(current) => (
          <>
            <Switch>
              <Match when={books.state() === "failed"}>
                <div class="mt-8">
                  <Failure error={books.error()} />
                </div>
              </Match>
              <Match when={true}>
                <ul class="mt-8 divide-y border-y">
                  <For each={books.items()}>
                    {(book) => (
                      <li class="flex items-center gap-2">
                        <Link
                          to="/read/$server/$publicationId"
                          params={{ server: accountKey(current()), publicationId: String(book.id) }}
                          class="group flex min-w-0 flex-1 items-center gap-3.5 py-3 focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
                        >
                          <div class="w-12 shrink-0">
                            <Cover
                              account={current()}
                              path={book.hasCover ? coverPath(book) : undefined}
                              title=""
                              class="rounded-sm"
                            />
                          </div>
                          <span class="grid min-w-0 gap-0.5">
                            <span class="truncate text-[17px] group-hover:text-link">
                              {publicationTitle(book)}
                            </span>
                            <span class="truncate text-sm text-muted-foreground">
                              {bookDetail(book, progressCaption(progressOf(book)))}
                            </span>
                          </span>
                        </Link>
                        <Link
                          to="/shared/$server/books/$publicationId"
                          params={{ server: accountKey(current()), publicationId: String(book.id) }}
                          aria-label={`About ${publicationTitle(book)}`}
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
          </>
        )}
      </Show>
    </Screen>
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
