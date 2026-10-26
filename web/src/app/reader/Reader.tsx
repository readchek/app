import { Match, Switch, createResource } from "solid-js"
import { Link, useNavigate, useParams } from "@tanstack/solid-router"
import { AlertCircle, Spinner } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { buttonVariants } from "../../components/ui/button.tsx"
import { type Account, accountByKey, accountKey } from "../accounts.ts"
import {
  type PageInfo,
  type Progress,
  type PublicationDetail,
  comicFormats,
  pagePath,
  pages,
  progress,
  publication,
  saveProgress,
  seriesPublications,
} from "../client.ts"
import { publicationTitle, seriesTitle } from "../titles.ts"
import { type ComicBook, ComicReader } from "./ComicReader.tsx"

/** A publication open full screen, in the reader its format needs. */
export function Reader() {
  const params = useParams({ from: "/read/$server/$publicationId" })
  const navigate = useNavigate()
  const account = () => accountByKey(params().server)
  const id = () => Number(params().publicationId)

  const [opened] = createResource(
    () => {
      const current = account()
      return current && !current.expired && Number.isInteger(id())
        ? { account: current, id: id() }
        : undefined
    },
    async ({ account, id }) => {
      const detail = await publication(account, id)
      const [pageList, saved] = await Promise.all([
        comicFormats.includes(detail.format) ? pages(account, id) : Promise.resolve([]),
        progress(account, id),
      ])
      return { account, detail, pages: pageList, progress: saved }
    },
  )

  return (
    <div class="fixed inset-0 bg-background text-foreground">
      <Switch>
        <Match when={!account() || account()?.expired}>
          <Message text="Sign in to this book's server to read it." />
        </Match>
        <Match when={opened.error}>
          <Message
            text={
              opened.error instanceof Error ? opened.error.message : "This book couldn't be opened."
            }
          />
        </Match>
        {/* Keyed, so the next book in the series opens a fresh reader. */}
        <Match when={opened()} keyed>
          {(book) => (
            <Switch>
              <Match when={comicFormats.includes(book.detail.format)}>
                <ComicReader
                  book={publicationComic(book, (id) =>
                    navigate({
                      to: "/read/$server/$publicationId",
                      params: { server: params().server, publicationId: String(id) },
                      replace: true,
                    }),
                  )}
                />
              </Match>
              <Match when={true}>
                <Message text="Books open on the web in a later version. Comics open now." />
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

/** A publication's pages, read with its place kept on the server. */
function publicationComic(
  opened: { account: Account; detail: PublicationDetail; pages: PageInfo[]; progress: Progress },
  open: (id: number) => void,
): ComicBook {
  const { account, detail } = opened
  let revision = opened.progress.revision
  return {
    account,
    title: publicationTitle(detail),
    subtitle: seriesTitle(detail),
    pages: opened.pages.map((page) => pagePath(detail.id, page.index)),
    start: opened.progress.locator,
    seriesKey: `${accountKey(account)}/${detail.series.id}`,
    direction: detail.readingDirection,
    positions: {
      save: async (locator) => {
        revision = (await saveProgress(account, detail.id, revision, locator)).revision
      },
      prefer: (other) => {
        revision = other.revision
      },
    },
    next: async () => {
      // The book after this one in its series, for the end of the book.
      const list = await seriesPublications(account, detail.series.id, { limit: 500 })
      const index = list.items.findIndex((item) => item.id === detail.id)
      const after = index >= 0 ? list.items[index + 1] : undefined
      return after && { title: publicationTitle(after), open: () => open(after.id) }
    },
  }
}

/** Says why the reader can't open something, with the way back. */
export function Message(props: { text: string }) {
  return (
    <div class="mx-auto flex h-full max-w-md flex-col items-start justify-center gap-6 px-6">
      <Alert variant="destructive">
        <AlertCircle />
        <p>{props.text}</p>
      </Alert>
      <Link to="/" class={buttonVariants({ variant: "outline" })}>
        Back to Reading Now
      </Link>
    </div>
  )
}
