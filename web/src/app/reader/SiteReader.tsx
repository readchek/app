import { Match, Switch, createResource } from "solid-js"
import { useNavigate, useParams, useSearch } from "@tanstack/solid-router"
import { Spinner } from "../../components/icons.tsx"
import { type Account, accountByKey, accountKey } from "../accounts.ts"
import {
  type ChapterContent,
  type RemoteChapter,
  type RemoteSeries,
  chapterContent,
  siteChapters,
  siteSeries,
} from "../sites/api.ts"
import { chapterPosition, savePosition } from "../sites/positions.ts"
import { chapterTitle } from "../sites/titles.ts"
import { type ComicBook, ComicReader } from "./ComicReader.tsx"
import { Message } from "./Reader.tsx"

/** A chapter read straight from a site, full screen. */
export function SiteReader() {
  const params = useParams({ from: "/chapter/$server/$extensionId" })
  const search = useSearch({ from: "/chapter/$server/$extensionId" })
  const navigate = useNavigate()
  const account = () => accountByKey(params().server)

  const [opened] = createResource(
    () => {
      const current = account()
      const { series, chapter, title } = search()
      return current && !current.expired && series && chapter
        ? {
            account: current,
            extensionId: params().extensionId,
            seriesId: series,
            chapterId: chapter,
            title,
          }
        : undefined
    },
    async ({ account, extensionId, seriesId, chapterId, title }) => {
      const [series, content] = await Promise.all([
        siteSeries(account, extensionId, seriesId),
        chapterContent(account, extensionId, chapterId),
      ])
      // Chapters can't be read one at a time, so the link that opens one
      // brings its title along.
      return { account, extensionId, series, content, chapterId, title }
    },
  )

  return (
    <div class="fixed inset-0 bg-background text-foreground">
      <Switch>
        <Match when={!account() || account()?.expired}>
          <Message text="Sign in to this site's server to read it." />
        </Match>
        <Match when={opened.error}>
          <Message
            text={
              opened.error instanceof Error
                ? opened.error.message
                : "This chapter couldn't be opened."
            }
          />
        </Match>
        <Match when={opened()} keyed>
          {(chapter) => (
            <Switch>
              <Match when={chapter.content.pages}>
                <ComicReader
                  book={siteComic(chapter, (next) =>
                    navigate({
                      to: "/chapter/$server/$extensionId",
                      params: { server: params().server, extensionId: chapter.extensionId },
                      search: {
                        series: chapter.series.id,
                        chapter: next.id,
                        title: chapterTitle(next),
                      },
                      replace: true,
                    }),
                  )}
                />
              </Match>
              <Match when={true}>
                <Message text="Books from sites open on the web in a later version. Comics open now." />
              </Match>
            </Switch>
          )}
        </Match>
        <Match when={true}>
          <p
            role="status"
            class="flex h-full items-center justify-center gap-2.5 text-muted-foreground"
          >
            <Spinner class="size-[18px] text-link" />
            Opening…
          </p>
        </Match>
      </Switch>
    </div>
  )
}

function siteComic(
  opened: {
    account: Account
    extensionId: string
    series: RemoteSeries
    content: ChapterContent
    chapterId: string
    title: string | undefined
  },
  open: (chapter: RemoteChapter) => void,
): ComicBook {
  const { account, extensionId, series, chapterId } = opened
  const server = accountKey(account)
  const pages = [...(opened.content.pages ?? [])].sort((a, b) => a.index - b.index)
  const title = opened.title ?? series.title
  const direction =
    series.readingDirection === "rtl" ? "rtl" : series.readingDirection === "ltr" ? "ltr" : null
  return {
    account,
    title,
    subtitle: series.title,
    pages: pages.map((page) => page.url),
    start: chapterPosition(server, extensionId, chapterId)?.locator ?? null,
    seriesKey: `${server}/${extensionId}/${series.id}`,
    direction,
    positions: {
      save: async (locator) => {
        savePosition({
          server,
          extensionId,
          seriesId: series.id,
          seriesTitle: series.title,
          chapterId,
          chapterTitle: title,
          coverUrl: series.coverUrl,
          direction,
          locator,
          progression: locator.locations?.totalProgression ?? 0,
          openedAt: new Date().toISOString(),
        })
      },
      // Only the server's positions can be overtaken by another device.
      prefer: () => {},
    },
    next: async () => {
      const page = await siteChapters(account, extensionId, {
        seriesId: series.id,
        order: "asc",
        after: chapterId,
        limit: 1,
      })
      const after = page.items[0]
      return after && { title: chapterTitle(after), open: () => open(after) }
    },
  }
}
