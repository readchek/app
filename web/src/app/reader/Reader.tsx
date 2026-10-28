import { Match, Switch } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { DrmError, Epub, type Publication, TextBook } from "@readchek/reader"
import type { PdfDocument } from "@readchek/reader/pdf"
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
import { loadFile } from "../files.ts"
import { publicationTitle, seriesTitle } from "../titles.ts"
import { type BookSource, BookReader } from "./BookReader.tsx"
import { type ComicBook, ComicReader, serverPages } from "./ComicReader.tsx"
import { type Positions, type UpNext, createReaderKeys, useCloseReader } from "./shared.tsx"

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
      const [pageList, saved, book] = await Promise.all([
        comicFormats.includes(detail.format) ? pages(account, id) : Promise.resolve([]),
        progress(account, id),
        // Named as the iOS app names its download, since a text file's
        // name can become its title, and so the size of its pages.
        openBook(
          account,
          `/api/v1/publications/${id}/file`,
          detail.format,
          `${id}.${detail.format}`,
        ),
      ])
      return { account, detail, pages: pageList, progress: saved, book }
    },
  )

  const openNext = (id: number) =>
    navigate({
      to: "/read/$server/$publicationId",
      params: { server: params().server, publicationId: String(id) },
      replace: true,
    })

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
                <ComicReader book={publicationComic(book, openNext)} />
              </Match>
              <Match when={book.book?.kind === "book" && book.book.publication} keyed>
                {(publication) => (
                  <BookReader book={publicationBook(book, publication, openNext)} />
                )}
              </Match>
              <Match when={book.book?.kind === "pdf" && book.book.pdf} keyed>
                {(pdf) => <ComicReader book={publicationPdf(book, pdf, openNext)} />}
              </Match>
              <Match when={true}>
                <Message text={laterFormat} />
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

type Opened = {
  account: Account
  detail: PublicationDetail
  pages: PageInfo[]
  progress: Progress
}

/** A publication's place, kept on the server. */
function serverPositions(account: Account, id: number, saved: Progress): Positions {
  let revision = saved.revision
  return {
    save: async (locator) => {
      revision = (await saveProgress(account, id, revision, locator)).revision
    },
    prefer: (other) => {
      revision = other.revision
    },
  }
}

/** The book after this one in its series, for the end of the book. */
function nextInSeries(
  account: Account,
  detail: PublicationDetail,
  open: (id: number) => void,
): () => Promise<UpNext | undefined> {
  return async () => {
    const list = await seriesPublications(account, detail.series.id, { limit: 200 })
    const index = list.items.findIndex((item) => item.id === detail.id)
    const after = index >= 0 ? list.items[index + 1] : undefined
    return after && { title: publicationTitle(after), open: () => open(after.id) }
  }
}

/** A publication's pages, read with its place kept on the server. */
function publicationComic(opened: Opened, open: (id: number) => void): ComicBook {
  const { account, detail } = opened
  return {
    account,
    title: publicationTitle(detail),
    subtitle: seriesTitle(detail),
    pages: serverPages(
      account,
      opened.pages.map((page) => pagePath(detail.id, page.index)),
    ),
    start: opened.progress.locator,
    seriesKey: `${accountKey(account)}/${detail.series.id}`,
    direction: detail.readingDirection,
    positions: serverPositions(account, detail.id, opened.progress),
    next: nextInSeries(account, detail, open),
  }
}

/** A publication's PDF, read page by page with its place kept on the server. */
function publicationPdf(opened: Opened, pdf: PdfDocument, open: (id: number) => void): ComicBook {
  return {
    ...publicationComic(opened, open),
    pages: pdf,
    toc: pdf.toc,
    release: () => void pdf.destroy(),
  }
}

/** A publication's book, read with its place kept on the server. */
function publicationBook(
  opened: Opened,
  book: Publication,
  open: (id: number) => void,
): BookSource {
  const { account, detail } = opened
  return {
    account,
    title: publicationTitle(detail),
    subtitle: seriesTitle(detail),
    publication: book,
    start: opened.progress.locator,
    positions: serverPositions(account, detail.id, opened.progress),
    next: nextInSeries(account, detail, open),
  }
}

/** What formats that don't open yet say. */
export const laterFormat =
  "This kind of book opens on the web in a later version. Comics, EPUB, PDF, plain text and Markdown open now."

/** A book file, opened in the reader its format needs. */
export type OpenedFile =
  | { kind: "book"; publication: Publication }
  | { kind: "pdf"; pdf: PdfDocument }

const pdfFiles = {
  worker: `${import.meta.env.BASE_URL}pdfjs/pdf.worker.min.mjs`,
  cMaps: `${import.meta.env.BASE_URL}pdfjs/cmaps/`,
  standardFonts: `${import.meta.env.BASE_URL}pdfjs/standard_fonts/`,
}

/**
 * Downloads a book, or the one kept from before, and opens it, when its
 * format reads on the web. Other formats give undefined.
 */
export async function openBook(
  account: Account,
  path: string,
  format: string,
  fileName: string,
): Promise<OpenedFile | undefined> {
  const open: ((file: Blob) => Promise<OpenedFile>) | undefined =
    format === "epub"
      ? async (file) => ({ kind: "book", publication: await Epub.open(file) })
      : format === "txt"
        ? async (file) => ({ kind: "book", publication: await TextBook.plainText(file, fileName) })
        : format === "markdown"
          ? async (file) => ({ kind: "book", publication: await TextBook.markdown(file, fileName) })
          : format === "pdf"
            ? async (file) => {
                // pdf.js loads only when a PDF opens.
                const { PdfDocument } = await import("@readchek/reader/pdf")
                return { kind: "pdf", pdf: await PdfDocument.open(file, pdfFiles) }
              }
            : undefined
  if (!open) return undefined
  const file = await loadFile(account, path)
  try {
    return await open(file)
  } catch (error) {
    if (error instanceof DrmError) throw error
    throw new Error(
      `This book couldn't be opened: ${error instanceof Error ? error.message : "the reader can't read its file."}`,
      { cause: error },
    )
  }
}

/** Says why the reader can't open something, with the way back. */
export function Message(props: { text: string }) {
  createReaderKeys({ close: useCloseReader() })
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
