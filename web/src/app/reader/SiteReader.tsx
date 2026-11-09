import { Match, Switch } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import type { Publication, ReadingDirection } from "@readchek/reader"
import { useNavigate, useParams, useSearch } from "@tanstack/solid-router"
import { Spinner } from "../../components/icons.tsx"
import { type Account, accountByKey, accountKey } from "../accounts.ts"
import {
  type ChapterContent,
  type RemoteChapter,
  type RemoteSeries,
  chapterContent,
  installedExtensions,
  siteChapters,
  siteSeries,
} from "../sites/api.ts"
import { chapterPosition, savePosition } from "../sites/positions.ts"
import { chapterTitle } from "../sites/titles.ts"
import { type BookSource, BookReader } from "./BookReader.tsx"
import type { CommentSource } from "./Comments.tsx"
import type { Neighbor, Neighbors, Positions } from "./shared.tsx"
import { type ComicBook, ComicReader, type SeriesEntry, serverPages } from "./ComicReader.tsx"
import { loadImage } from "../images.ts"
import { Message, laterFormat, openBook } from "./Reader.tsx"

// A chapter's content asked for ahead of opening it, while the last pages
// of the one before are read, so opening it finds the answer waiting.
const prepared = new Map<string, Promise<ChapterContent>>()

function contentOf(account: Account, extensionId: string, chapterId: string) {
  const key = `${accountKey(account)}\n${extensionId}\n${chapterId}`
  let content = prepared.get(key)
  if (!content) {
    content = chapterContent(account, extensionId, chapterId)
    prepared.set(key, content)
    // Kept only until it's used or fails; a chapter's pages can change.
    const forget = () => prepared.get(key) === content && prepared.delete(key)
    content.catch(forget)
    setTimeout(forget, 5 * 60 * 1000)
  }
  return content
}

/** The chapter next to `chapterId`, going on (`asc`) or back (`desc`). */
async function chapterBeside(
  account: Account,
  extensionId: string,
  seriesId: string,
  chapterId: string,
  order: "asc" | "desc",
): Promise<RemoteChapter | undefined> {
  const page = await siteChapters(account, extensionId, {
    seriesId,
    order,
    after: chapterId,
    limit: 1,
  })
  return page.items[0]
}

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
      // What's either side is asked for with the chapter itself, so the
      // way on is known before the first page shows. Reading goes on without.
      const beside = (order: "asc" | "desc") =>
        chapterBeside(account, extensionId, seriesId, chapterId, order).catch(() => undefined)
      const [series, content, after, before, extension] = await Promise.all([
        siteSeries(account, extensionId, seriesId),
        contentOf(account, extensionId, chapterId),
        beside("asc"),
        beside("desc"),
        // Only to know whether it shows readers' comments; reading goes on without.
        installedExtensions(account).then(
          (all) => all.find((one) => one.id === extensionId),
          () => undefined,
        ),
      ])
      const book = content.file
        ? await openBook(
            account,
            content.file.url,
            content.format,
            content.file.fileName ?? `${chapterId}.${content.format}`,
          )
        : undefined
      // Chapters can't be read one at a time, so the link that opens one
      // brings its title along.
      const comments: CommentSource | undefined = extension?.comments && {
        account,
        extensionId,
        chapterId,
        site: extension.name,
        orders: extension.comments,
      }
      return {
        account,
        extensionId,
        series,
        content,
        book,
        chapterId,
        title,
        comments,
        after,
        before,
      }
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
          {(chapter) => {
            const open = (next: RemoteChapter) =>
              navigate({
                to: "/chapter/$server/$extensionId",
                params: {
                  server: params().server,
                  extensionId: chapter.extensionId,
                },
                search: {
                  series: chapter.series.id,
                  chapter: next.id,
                  title: chapterTitle(next),
                },
                replace: true,
              })
            return (
              <Switch>
                <Match when={chapter.content.pages}>
                  <ComicReader book={siteComic(chapter, open)} />
                </Match>
                <Match when={chapter.book?.kind === "book" && chapter.book.publication} keyed>
                  {(publication) => <BookReader book={siteBook(chapter, publication, open)} />}
                </Match>
                <Match when={chapter.book?.kind === "pdf" && chapter.book.pdf} keyed>
                  {(pdf) => (
                    <ComicReader
                      book={{
                        ...siteComic(chapter, open),
                        fixedLayout: true,
                        pages: pdf,
                        toc: pdf.toc,
                        release: () => void pdf.destroy(),
                      }}
                    />
                  )}
                </Match>
                <Match when={true}>
                  <Message text={laterFormat} />
                </Match>
              </Switch>
            )
          }}
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

type OpenedChapter = {
  account: Account
  extensionId: string
  series: RemoteSeries
  content: ChapterContent
  chapterId: string
  title: string | undefined
  comments: CommentSource | undefined
  after: RemoteChapter | undefined
  before: RemoteChapter | undefined
}

// Where a site chapter keeps its place, in this browser, and what comes after it.
function sitePlace(opened: OpenedChapter, open: (chapter: RemoteChapter) => void) {
  const { account, extensionId, series, chapterId } = opened
  const server = accountKey(account)
  const title = opened.title ?? series.title
  const direction: ReadingDirection | null =
    series.readingDirection === "rtl" ? "rtl" : series.readingDirection === "ltr" ? "ltr" : null
  const neighbor = (chapter: RemoteChapter | undefined): Neighbor | undefined =>
    chapter && {
      title: chapterTitle(chapter),
      open: () => open(chapter),
      prepare: () => {
        // The page list, then the first pages, which the image cache keeps.
        void contentOf(account, extensionId, chapter.id).then(
          (content) => {
            const first = [...(content.pages ?? [])].sort((a, b) => a.index - b.index).slice(0, 3)
            for (const page of first) loadImage(account, page.url).catch(() => {})
          },
          () => {},
        )
      },
    }
  const neighbors: Neighbors = {
    previous: neighbor(opened.before),
    next: neighbor(opened.after),
    // Sites mostly carry series still coming out, so one whose status
    // isn't known is taken to be.
    ending: series.status === "completed" || series.status === "cancelled" ? "last" : "caughtUp",
    unit: "chapter",
  }
  /** Every chapter of the series, oldest first, a server page at a time. */
  const all = async (): Promise<SeriesEntry[]> => {
    const entries: SeriesEntry[] = []
    let offset: number | null = 0
    // A bound, so a server that keeps answering can't keep this going for ever.
    for (let pages = 0; offset !== null && pages < 50; pages++) {
      const page: Awaited<ReturnType<typeof siteChapters>> = await siteChapters(
        account,
        extensionId,
        { seriesId: series.id, order: "asc", offset, limit: 200 },
      )
      for (const chapter of page.items) {
        entries.push({
          title: chapterTitle(chapter),
          current: chapter.id === chapterId,
          open: () => open(chapter),
        })
      }
      offset = page.nextOffset
    }
    return entries
  }
  return {
    neighbors,
    all,
    account,
    title,
    server,
    direction,
    start: chapterPosition(server, extensionId, chapterId)?.locator ?? null,
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
    } satisfies Positions,
  }
}

function siteComic(opened: OpenedChapter, open: (chapter: RemoteChapter) => void): ComicBook {
  const place = sitePlace(opened, open)
  const pages = [...(opened.content.pages ?? [])].sort((a, b) => a.index - b.index)
  return {
    account: place.account,
    title: place.title,
    subtitle: opened.series.title,
    pages: serverPages(
      place.account,
      pages.map((page) => page.url),
    ),
    start: place.start,
    seriesKey: `${place.server}/${opened.extensionId}/${opened.series.id}`,
    direction: opened.series.readingDirection,
    positions: place.positions,
    neighbors: place.neighbors,
    series: place.all,
    comments: opened.comments,
  }
}

function siteBook(
  opened: OpenedChapter,
  book: Publication,
  open: (chapter: RemoteChapter) => void,
): BookSource {
  const place = sitePlace(opened, open)
  // A site's book is often the whole series, so it goes by the book's own title.
  const title = book.metadata.title || place.title
  return {
    account: place.account,
    title,
    subtitle: title === opened.series.title ? undefined : opened.series.title,
    publication: book,
    start: place.start,
    positions: place.positions,
    neighbors: place.neighbors,
    comments: opened.comments,
  }
}
