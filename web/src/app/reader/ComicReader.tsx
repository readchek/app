import { Show, createMemo, createSignal, onCleanup, onMount } from "solid-js"
import { Portal } from "solid-js/web"
import { createResource } from "../../lib/resource.ts"
import {
  type ComicLocation,
  ComicView,
  type Locator,
  type PageSource,
  type TocItem,
  comicPageIndex,
} from "@readchek/reader"
import { ListBullet, Sliders } from "../../components/icons.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import {
  Popover,
  PopoverContent,
  PopoverTitle,
  PopoverTrigger,
} from "../../components/ui/popover.tsx"
import {
  Slider,
  SliderFill,
  SliderLabel,
  SliderThumb,
  SliderTrack,
} from "../../components/ui/slider.tsx"
import { Choice } from "../../components/Choice.tsx"
import { cn } from "../../lib/cn.ts"
import type { Account } from "../accounts.ts"
import { loadImage } from "../images.ts"
import {
  type CommentSource,
  CommentSettings,
  CommentsButton,
  CommentsLink,
  CommentsPanel,
  PANEL_WIDTH,
  createComments,
  isDocked,
} from "./Comments.tsx"
import { ContentsDialog } from "./Contents.tsx"
import { ChapterEndPage, ChapterStartPage } from "./ChapterEnd.tsx"
import { type ReadingMode, type SourceDirection, layoutFor, modeNames } from "./modes.ts"
import {
  changeComicSettings,
  comicSettings,
  seriesGuess,
  seriesMode,
  setSeriesGuess,
  setSeriesMode,
} from "./settings.ts"
import {
  BottomBar,
  ChapterButtons,
  ConflictDialog,
  type Neighbor,
  type Neighbors,
  PageButtons,
  type Positions,
  TopBar,
  arriveBy,
  createControls,
  createKeeper,
  createReaderKeys,
  settleWheel,
  takeArrival,
  useCloseReader,
} from "./shared.tsx"

/** One of a series' chapters or books, for moving between them without leaving the reader. */
export type SeriesEntry = { title: string; current: boolean; open: () => void }

/** A comic or PDF to read: its pages, and where to start and keep its place. */
export type ComicBook = {
  account: Account
  title: string
  subtitle?: string
  pages: PageSource
  /** A PDF's outline. */
  toc?: TocItem[]
  /** Frees what the pages hold once the reader closes, such as an open PDF. */
  release?: () => void
  start: Locator | null
  /** Names the series for how it's chosen to be read, with its server. */
  seriesKey: string
  /** Which way its source says it reads, if it says. */
  direction: SourceDirection
  /** Whether its pages are always pages, as a PDF's are, so there's no way of reading to choose. */
  fixedLayout?: boolean
  positions: Positions
  /** What's either side of it, when it's one of a series. */
  neighbors?: Neighbors
  /** Everything in its series, in reading order, asked for when the list opens. */
  series?: () => Promise<SeriesEntry[]>
  /** Where readers' comments on it come from, for a chapter from a site that has them. */
  comments?: CommentSource
}

/** Pages from paths on the account's server, such as a comic's. */
export function serverPages(account: Account, paths: string[]): PageSource {
  return {
    count: paths.length,
    load: (index) => loadImage(account, paths[index]!),
  }
}

/** A comic open full screen: the pages, and controls that appear on a tap in the middle. */
export function ComicReader(props: { book: ComicBook }) {
  let element: HTMLDivElement | undefined
  let view: ComicView | undefined

  const book = props.book
  const neighbors = book.neighbors
  // Read into from the chapter before or after, or opened from a list.
  const arrival = takeArrival()

  const mode = (): ReadingMode => (book.fixedLayout ? "comic" : seriesMode(book.seriesKey))
  const layout = () => layoutFor(mode(), book.direction, seriesGuess(book.seriesKey))
  // What the view made of pages nothing else spoke for.
  const [decided, setDecided] = createSignal<"paged" | "scrolled">()
  const flow = () => {
    const chosen = layout().flow
    return chosen === "automatic" ? decided() : chosen
  }
  const motion = () => (flow() === "scrolled" ? "scroll" : "turn")
  const rtl = () => layout().direction === "rtl" && flow() !== "scrolled"

  const count = () => book.pages.count
  const pageOf = (locator: Locator | null) =>
    locator && book.pages.pageIndex
      ? book.pages.pageIndex(locator)
      : comicPageIndex(locator, count())
  const [contents, setContents] = createSignal(false)
  const [location, setLocation] = createSignal<ComicLocation>()
  const [scrub, setScrub] = createSignal<number>()
  // Reading into a chapter comes without the controls: nobody asked for them.
  const controls = createControls({ hidden: arrival !== undefined })
  const comments = book.comments && createComments(book.comments)
  const [leaving, setLeaving] = createSignal<"before" | "after">()
  const keeper = createKeeper(book.positions)
  const [seriesList] = createResource(
    () => (contents() && book.series ? book.series : undefined),
    (list) => list(),
  )
  // + and − zoom a comic's page, as they change a book's text size.
  createReaderKeys({
    close: useCloseReader(),
    larger: () => view?.zoomBy(1.25),
    smaller: () => view?.zoomBy(0.8),
  })

  /** Opens a chapter either side, saying how it was reached. */
  const go = (neighbor: Neighbor, from?: "start" | "end") => {
    if (leaving()) return
    setLeaving(neighbor === neighbors?.previous ? "before" : "after")
    arriveBy(from)
    neighbor.open(from)
  }

  // The pages either side of the chapter: one element each, placed by the
  // view in the flow of the pages and drawn here.
  const ends = {
    before: neighbors?.previous ? document.createElement("div") : undefined,
    after: neighbors ? document.createElement("div") : undefined,
  }
  for (const end of [ends.before, ends.after]) end?.style.setProperty("height", "100%")

  onMount(() => {
    if (!element) return
    // A chapter finished before starts over, since its last page is no
    // place to pick it up again.
    const finishedBefore = (book.start?.locations?.totalProgression ?? 0) >= 1
    const start =
      arrival === "end" ? ("end" as const) : arrival === "start" || finishedBefore ? 0 : book.start
    let lastPage: number | undefined
    let prepared = false
    view = new ComicView(
      element,
      book.pages,
      {
        location: (place) => {
          setLocation(place)
          setScrub(undefined)
          if (lastPage !== undefined && lastPage !== place.page) controls.read()
          lastPage = place.page
          // The view exists by its second report; its first comes as it's made.
          queueMicrotask(() => {
            const made = view?.currentFlow
            if (!made) return
            setDecided(made)
            if (layout().flow === "automatic") setSeriesGuess(book.seriesKey, made)
          })
          // The next chapter is fetched while the last pages are read, so
          // going on to it has nothing to wait for.
          if (!prepared && (place.atEnd || place.page >= count() - 3)) {
            prepared = true
            neighbors?.next?.prepare?.()
          }
          // The server counts a book finished only at 1, and a comic's
          // last page starts short of it, so reaching it says so outright.
          const locator = place.atEnd
            ? {
                ...place.locator,
                locations: { ...place.locator.locations, totalProgression: 1 },
              }
            : place.locator
          keeper.keep(locator)
        },
        tap: () => controls.tap(),
        leave: (toward) => {
          const neighbor = toward === "after" ? neighbors?.next : neighbors?.previous
          if (neighbor) go(neighbor, toward === "after" ? "start" : "end")
        },
      },
      { spreads: comicSettings().spreads, flow: layout().flow, direction: layout().direction },
      start,
      ends,
    )
    element.focus({ preventScroll: true })
    onCleanup(() => {
      view?.destroy()
      book.release?.()
    })
  })

  const choose = (chosen: ReadingMode) => {
    setSeriesMode(book.seriesKey, chosen)
    setDecided(undefined)
    view?.setOptions({ flow: layout().flow, direction: layout().direction })
  }

  const shownPage = () => scrub() ?? location()?.page ?? 0
  const pageLabel = () => {
    const place = location()
    if (!place) return ""
    if (scrub() === undefined && place.edge === "after") return "Finished"
    const pages = scrub() === undefined ? place.pages : [shownPage()]
    const first = pages[0]! + 1
    const last = pages[pages.length - 1]! + 1
    return `${first === last ? `Page ${first}` : `Pages ${first}–${last}`} of ${place.count}`
  }
  // What Automatic made of this series, said under the choice.
  const reads = () => {
    const known = layout().reads ?? (decided() === "scrolled" ? "webtoon" : decided() && "comic")
    return known ? modeNames[known] : undefined
  }
  const seriesItems = createMemo((): TocItem[] =>
    (seriesList() ?? []).map((entry, index) => ({
      title: entry.title,
      href: String(index),
      children: [],
    })),
  )
  const hasContents = () => (book.toc?.length ?? 0) > 0 || book.series !== undefined

  return (
    <div
      ref={(node) => arrival && settleWheel(node)}
      class="relative h-full transition-[margin] duration-200"
      // The page makes room for the comments beside it rather than going under them.
      style={{ "margin-right": isDocked(comments) ? `${PANEL_WIDTH}px` : "0" }}
      onPointerMove={(event) => {
        if (event.pointerType === "mouse" && (event.movementX || event.movementY)) controls.moved()
      }}
    >
      <div ref={(node) => (element = node)} class="absolute inset-0" aria-label="Pages" />

      <Show when={neighbors && ends.after}>
        <Portal mount={ends.after} ref={(node) => (node.style.height = "100%")}>
          <ChapterEndPage
            finished={book.title}
            neighbors={neighbors!}
            motion={motion()}
            opening={leaving() === "after"}
            go={(neighbor) => go(neighbor, "start")}
          >
            <Show when={comments}>{(shown) => <CommentsLink comments={shown()} />}</Show>
          </ChapterEndPage>
        </Portal>
      </Show>
      <Show when={ends.before && neighbors?.previous}>
        {(previous) => (
          <Portal mount={ends.before} ref={(node) => (node.style.height = "100%")}>
            <ChapterStartPage
              previous={previous()}
              motion={motion()}
              opening={leaving() === "before"}
              go={(neighbor) => go(neighbor, "end")}
            />
          </Portal>
        )}
      </Show>

      <TopBar controls={controls} title={book.title} subtitle={book.subtitle}>
        <Show when={comments}>{(shown) => <CommentsButton comments={shown()} />}</Show>
        <Show when={hasContents()}>
          <Button
            variant="ghost"
            size="sm"
            class="size-10 px-0 [&_svg]:size-5"
            aria-label={book.toc ? "Contents" : "Chapters"}
            onClick={() => {
              setContents(true)
              controls.hold("contents", true)
            }}
          >
            <ListBullet />
          </Button>
        </Show>
        <Popover
          placement="bottom-end"
          gutter={8}
          onOpenChange={(open) => controls.hold("settings", open)}
        >
          <PopoverTrigger
            class={cn(
              buttonVariants({ variant: "ghost", size: "sm" }),
              "size-10 px-0 [&_svg]:size-5",
            )}
            aria-label="Reading settings"
          >
            <Sliders />
          </PopoverTrigger>
          <PopoverContent class="grid gap-5">
            <PopoverTitle>Reading settings</PopoverTitle>
            <Show when={!book.fixedLayout}>
              <div class="grid gap-2">
                <Choice
                  label="Read as"
                  value={mode()}
                  options={[
                    { value: "automatic", label: "Auto" },
                    { value: "comic", label: "Comic" },
                    { value: "manga", label: "Manga" },
                    { value: "webtoon", label: "Webtoon" },
                  ]}
                  onChange={choose}
                />
                <p class="text-[13px] text-muted-foreground">
                  <Show when={mode() === "automatic"} fallback={reads()?.does}>
                    <Show when={reads()} fallback="Chek is looking at the pages.">
                      {(found) => (
                        <>
                          Reading as a {found().name.toLowerCase()}. {found().does}
                        </>
                      )}
                    </Show>
                  </Show>{" "}
                  Kept for this series.
                </p>
              </div>
            </Show>
            {/* Only pages can sit side by side. */}
            <Show when={flow() !== "scrolled"}>
              <Choice
                label="Two pages at once"
                value={comicSettings().spreads}
                options={[
                  { value: "automatic", label: "When wide" },
                  { value: "single", label: "Never" },
                  { value: "double", label: "Always" },
                ]}
                onChange={(spreads) => {
                  changeComicSettings({ spreads })
                  view?.setOptions({ spreads })
                }}
              />
            </Show>
            <Show when={book.comments}>{(source) => <CommentSettings source={source()} />}</Show>
          </PopoverContent>
        </Popover>
      </TopBar>

      <Show when={comments}>{(shown) => <CommentsPanel comments={shown()} />}</Show>

      <Show when={flow() !== "scrolled"}>
        <PageButtons
          controls={controls}
          rtl={rtl()}
          previous={() => view?.previous()}
          next={() => view?.next()}
        />
      </Show>

      <BottomBar controls={controls}>
        <Slider
          class="flex-row"
          value={[shownPage()]}
          minValue={0}
          maxValue={Math.max(count() - 1, 1)}
          inverted={rtl()}
          getValueLabel={(params) => `Page ${params.values[0]! + 1} of ${count()}`}
          onChange={(values) => setScrub(values[0]!)}
          onChangeEnd={(values) => view?.goTo(values[0]!)}
          disabled={count() < 2}
        >
          <SliderLabel class="sr-only">Page</SliderLabel>
          <SliderTrack>
            <SliderFill />
            <SliderThumb />
          </SliderTrack>
        </Slider>
        <ChapterButtons neighbors={neighbors} rtl={rtl()} go={(neighbor) => go(neighbor)}>
          <p class="text-center text-[13px] text-muted-foreground tabular-nums" aria-live="polite">
            {pageLabel()}
          </p>
        </ChapterButtons>
      </BottomBar>

      <ContentsDialog
        open={contents()}
        onOpenChange={(open) => {
          setContents(open)
          controls.hold("contents", open)
        }}
        title={book.toc ? undefined : "Chapters"}
        loading={!book.toc && seriesList() === undefined}
        items={book.toc ?? seriesItems()}
        current={
          book.toc ? undefined : seriesItems().find((_, index) => seriesList()?.[index]?.current)
        }
        choose={(item) => {
          setContents(false)
          controls.hold("contents", false)
          if (!book.toc) {
            const entry = seriesList()?.[Number(item.href)]
            if (entry && !entry.current) {
              arriveBy(undefined)
              entry.open()
            }
            return
          }
          const index = pageOf({ href: item.href, type: "application/pdf" })
          if (index !== undefined) view?.goTo(index)
          controls.hide()
        }}
      />

      <ConflictDialog
        keeper={keeper}
        place={(other) => {
          const index = pageOf(other.locator)
          return index === undefined ? "another place" : `page ${index + 1}`
        }}
        onTake={(other) => {
          const index = pageOf(other.locator)
          if (index !== undefined) view?.goTo(index)
        }}
      />
    </div>
  )
}
