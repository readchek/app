import { For, Match, Show, Switch, createMemo, createResource, createSignal } from "solid-js"
import { Link, useNavigate, useParams, useSearch } from "@tanstack/solid-router"
import { ArrowUpDown } from "../../components/icons.tsx"
import { Badge } from "../../components/ui/badge.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import { Select } from "../../components/ui/select.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { cn } from "../../lib/cn.ts"
import { type Account, accountKey } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
import { Cover } from "../Cover.tsx"
import { createPagedList } from "../paged.ts"
import { paragraphs } from "../shared/Book.tsx"
import { Failure } from "../shared/Library.tsx"
import { routeAccount } from "../shared/data.ts"
import {
  type ChapterOrder,
  type RemoteChapter,
  type RemoteSeries,
  setReleaseGroup,
  siteChapters,
  siteSeries,
} from "./api.ts"
import { chapterPage, siteInfo } from "./data.ts"
import { Follow } from "./Follow.tsx"
import { chapterPosition, lastInSeries } from "./positions.ts"
import { SiteFailure } from "./SiteFailure.tsx"
import { chapterTitle, statusLabel } from "./titles.ts"

/** A series on a site: what the site says about it, the button that picks up where you are, and its chapters. */
export function SiteSeries() {
  const navigate = useNavigate()
  const params = useParams({ from: "/app/sites/$server/$extensionId/series" })
  const search = useSearch({ from: "/app/sites/$server/$extensionId/series" })
  const account = createMemo(() => {
    try {
      return routeAccount(params().server)
    } catch {
      return undefined
    }
  })
  const extensionId = () => params().extensionId
  const seriesId = () => search().id

  const [info] = createResource(
    () => account() && { account: account()!, id: extensionId() },
    ({ account, id }) => siteInfo(account, id),
  )
  const [series, { refetch }] = createResource(
    () => account() && { account: account()!, id: extensionId(), seriesId: seriesId() },
    ({ account, id, seriesId }) => siteSeries(account, id, seriesId),
  )

  return (
    <Screen
      title=""
      back={
        <BackButton
          label={info()?.name ?? "Back"}
          fallback={() =>
            void navigate({
              to: "/sites/$server/$extensionId",
              params: { server: params().server, extensionId: extensionId() },
            })
          }
        />
      }
      narrow
    >
      <Switch>
        <Match when={!account()}>
          <Failure
            error={new Error("You're not signed in to this site's server. Add it in Settings.")}
          />
        </Match>
        <Match when={series.error}>
          <SiteFailure
            account={account()!}
            site={info()}
            error={series.error}
            retry={() => void refetch()}
          />
        </Match>
        <Match when={series()} keyed>
          {(found) => (
            <SeriesBody account={account()!} extensionId={extensionId()} series={found} />
          )}
        </Match>
        <Match when={true}>
          <div class="flex items-end gap-5" aria-hidden="true">
            <Skeleton class="aspect-[2/3] w-32 rounded-md sm:w-40" />
            <div class="grid gap-3 pb-1">
              <Skeleton class="h-8 w-48" />
              <Skeleton class="h-4 w-28" />
            </div>
          </div>
        </Match>
      </Switch>
    </Screen>
  )
}

function SeriesBody(props: { account: Account; extensionId: string; series: RemoteSeries }) {
  const server = accountKey(props.account)
  const [info] = createResource(() => siteInfo(props.account, props.extensionId))
  const [order, setOrder] = createSignal<ChapterOrder>("asc")
  const [counts, setCounts] = createSignal<{ total: number; chapterCount: number | null }>()
  const [preferred, setPreferred] = createSignal<string | null>(null)
  // Bumped when the preferred group changes, so the list is asked for again.
  const [picks, setPicks] = createSignal(0)
  const [expanded, setExpanded] = createSignal(false)

  const chapters = createPagedList(
    () => ({ order: order(), picks: picks() }),
    (key, cursor, signal) =>
      chapterPage(
        props.account,
        props.extensionId,
        props.series.id,
        key.order,
        cursor,
        signal,
        (page) => {
          setCounts({ total: page.total, chapterCount: page.chapterCount })
          setPreferred(page.preferredGroup)
        },
      ),
  )

  // The first chapter, for starting a series listed newest first.
  const [first] = createResource(
    () => ({ picks: picks() }),
    async () =>
      (
        await siteChapters(props.account, props.extensionId, {
          seriesId: props.series.id,
          order: "asc",
          limit: 1,
        })
      ).items[0],
  )

  const last = () => lastInSeries(server, props.extensionId, props.series.id)
  const authors = () => props.series.contributors.map((person) => person.name)
  const facts = () =>
    [statusLabel(props.series.status), props.series.year ? String(props.series.year) : undefined]
      .filter(Boolean)
      .join(" · ")
  const summary = () => (props.series.summary ? paragraphs(props.series.summary) : [])

  // Every group seen releasing a chapter, for choosing whose releases come first.
  const groups = createMemo(() => {
    const names = new Set<string>()
    for (const chapter of chapters.items()) {
      for (const release of chapter.releases)
        if (release.releaseGroup) names.add(release.releaseGroup)
    }
    return [...names].sort((a, b) => a.localeCompare(b))
  })
  const groupOptions = () => [
    { value: "", label: "Best release" },
    ...groups().map((name) => ({ value: name, label: name })),
  ]
  const chooseGroup = async (name: string) => {
    await setReleaseGroup(props.account, props.extensionId, props.series.id, name || null).catch(
      () => {},
    )
    setPreferred(name || null)
    setPicks((n) => n + 1)
  }

  const chapterLink = (chapter: RemoteChapter) => ({
    to: "/chapter/$server/$extensionId" as const,
    params: { server, extensionId: props.extensionId },
    search: { series: props.series.id, chapter: chapter.id, title: chapterTitle(chapter) },
  })

  return (
    <>
      <div class="flex flex-col gap-6 sm:flex-row sm:items-end sm:gap-7">
        <div class="w-40 shrink-0">
          <Cover
            account={props.account}
            path={props.series.coverUrl ?? undefined}
            title={props.series.title}
          />
        </div>
        <div class="min-w-0 pb-1">
          <h1 class="text-[30px] leading-[1.05] tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
            {props.series.title}
          </h1>
          <Show when={authors().length > 0}>
            <p class="mt-2 text-[17px]">{authors().join(", ")}</p>
          </Show>
          <Show when={facts()}>
            <p class="mt-1 text-[15px] text-muted-foreground">{facts()}</p>
          </Show>
        </div>
      </div>

      <div class="mt-6 flex flex-col gap-3 sm:flex-row">
        <Switch>
          <Match when={last()}>
            {(place) => (
              <Link
                to="/chapter/$server/$extensionId"
                params={{ server, extensionId: props.extensionId }}
                search={{
                  series: props.series.id,
                  chapter: place().chapterId,
                  title: place().chapterTitle,
                }}
                class={buttonVariants({ class: "w-full sm:w-auto sm:px-8" })}
              >
                <span class="truncate">Continue {place().chapterTitle}</span>
              </Link>
            )}
          </Match>
          <Match when={first()}>
            {(chapter) => (
              <Link
                {...chapterLink(chapter())}
                class={buttonVariants({ class: "w-full sm:w-auto sm:px-8" })}
              >
                Start Reading
              </Link>
            )}
          </Match>
        </Switch>
        <Show when={props.account.user.role === "admin" && !props.account.user.demo}>
          <Follow account={props.account} extensionId={props.extensionId} series={props.series} />
        </Show>
      </div>

      <Show when={props.series.tags.length > 0}>
        <ul class="mt-6 flex flex-wrap gap-2" aria-label="Genres and themes">
          <For each={props.series.tags}>
            {(tag) => (
              <li>
                <Badge variant="secondary">{tag}</Badge>
              </li>
            )}
          </For>
        </ul>
      </Show>

      <Show when={summary().length > 0}>
        <div class="mt-8 text-[17px] leading-relaxed">
          <div class={cn("grid gap-3", !expanded() && "line-clamp-4")}>
            <For each={summary()}>{(text) => <p class="[overflow-wrap:anywhere]">{text}</p>}</For>
          </div>
          <Show when={!expanded()}>
            <Button
              variant="link"
              size="inline"
              class="mt-1 text-[15px]"
              onClick={() => setExpanded(true)}
            >
              More
            </Button>
          </Show>
        </div>
      </Show>

      <div class="mt-10 flex flex-wrap items-center justify-between gap-3">
        <h2 class="text-[22px] leading-tight tracking-[-0.03em]">
          <Show when={counts()?.chapterCount} fallback="Chapters">
            {(count) => (count() === 1 ? "1 chapter" : `${count()} chapters`)}
          </Show>
        </h2>
        <div class="flex items-center gap-2">
          <Show when={groups().length > 1}>
            <Select
              label="Releases from"
              class="max-w-52"
              options={groupOptions()}
              value={groupOptions().find((option) => option.value === (preferred() ?? ""))}
              onChange={(option) => void chooseGroup(option.value)}
            />
          </Show>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setOrder((now) => (now === "asc" ? "desc" : "asc"))}
          >
            <ArrowUpDown />
            {order() === "asc" ? "Oldest first" : "Newest first"}
          </Button>
        </div>
      </div>

      <Switch>
        <Match when={chapters.state() === "failed" && chapters.items().length === 0}>
          <div class="mt-4">
            <SiteFailure
              account={props.account}
              site={info()}
              error={chapters.error()}
              retry={chapters.retry}
            />
          </div>
        </Match>
        <Match when={chapters.items().length === 0 && chapters.state() === "done"}>
          <p class="mt-4 text-[15px] text-muted-foreground">This series has no chapters yet.</p>
        </Match>
        <Match when={true}>
          <ul class="mt-3 divide-y border-y">
            <For each={chapters.items()}>
              {(chapter) => {
                const place = () => chapterPosition(server, props.extensionId, chapter.id)
                const finished = () => (place()?.progression ?? 0) >= 1
                return (
                  <li>
                    <Link
                      {...chapterLink(chapter)}
                      class="group flex items-center gap-3 py-3 focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
                    >
                      <span class="grid min-w-0 flex-1 gap-0.5">
                        <span
                          class={cn(
                            "truncate text-[17px] group-hover:text-link",
                            finished() && "text-muted-foreground",
                          )}
                        >
                          {chapterTitle(chapter)}
                        </span>
                        <span class="truncate text-sm text-muted-foreground">
                          {chapterDetail(chapter, place()?.progression)}
                        </span>
                      </span>
                      <Show when={place() && !finished()}>
                        <span class="size-2 shrink-0 rounded-full bg-link" aria-label="Started" />
                      </Show>
                    </Link>
                  </li>
                )
              }}
            </For>
          </ul>
          <Show when={chapters.state() === "loading"}>
            <div class="divide-y" aria-hidden="true">
              <For each={[0, 1, 2, 3]}>
                {() => (
                  <div class="grid gap-2 py-3.5">
                    <Skeleton class="h-4 w-56" />
                    <Skeleton class="h-3 w-28" />
                  </div>
                )}
              </For>
            </div>
          </Show>
          <Show when={chapters.state() === "failed"}>
            <div class="mt-4">
              <SiteFailure
                account={props.account}
                site={info()}
                error={chapters.error()}
                retry={chapters.retry}
              />
            </div>
          </Show>
          <div ref={chapters.sentinel} class="h-px" />
        </Match>
      </Switch>
    </>
  )
}

/** Who released a chapter, when, and how far you are into it. */
function chapterDetail(chapter: RemoteChapter, progression: number | undefined): string {
  const date = chapter.published ? new Date(chapter.published) : undefined
  const when =
    date && !Number.isNaN(date.getTime())
      ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(date)
      : undefined
  const status =
    progression === undefined
      ? undefined
      : progression >= 1
        ? "Read"
        : `${Math.max(1, Math.round(progression * 100))}%`
  const others = chapter.releases.length > 1 ? `${chapter.releases.length} releases` : undefined
  return [chapter.releaseGroup, when, others, status].filter(Boolean).join(" · ")
}
