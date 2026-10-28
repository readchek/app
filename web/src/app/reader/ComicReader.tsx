import { Show, createSignal, onCleanup, onMount } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import {
  type ComicLocation,
  ComicView,
  type Locator,
  type PageSource,
  type ReadingDirection,
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
import { Slider } from "../../components/ui/slider.tsx"
import { ToggleGroup } from "../../components/ui/toggle-group.tsx"
import { cn } from "../../lib/cn.ts"
import type { Account } from "../accounts.ts"
import { loadImage } from "../images.ts"
import { ContentsDialog } from "./Contents.tsx"
import {
  changeComicSettings,
  comicSettings,
  seriesDirection,
  setSeriesDirection,
} from "./settings.ts"
import {
  BottomBar,
  ConflictDialog,
  PageButtons,
  type Positions,
  TopBar,
  type UpNext,
  UpNextCard,
  createControls,
  createKeeper,
  createReaderKeys,
  useCloseReader,
} from "./shared.tsx"

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
  /** Names the series for its chosen reading direction, with its server. */
  seriesKey: string
  direction: ReadingDirection | null
  positions: Positions
  next: () => Promise<UpNext | undefined>
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
  const direction = (): ReadingDirection =>
    seriesDirection(book.seriesKey) ?? book.direction ?? "ltr"

  const count = () => book.pages.count
  const pageOf = (locator: Locator | null) =>
    locator && book.pages.pageIndex
      ? book.pages.pageIndex(locator)
      : comicPageIndex(locator, count())
  const [contents, setContents] = createSignal(false)
  const [location, setLocation] = createSignal<ComicLocation>()
  const [scrub, setScrub] = createSignal<number>()
  const controls = createControls()
  const [finished, setFinished] = createSignal(false)
  const keeper = createKeeper(book.positions)
  const [next] = createResource(() => book.next())
  // + and − zoom a comic's page, as they change a book's text size.
  createReaderKeys({
    close: useCloseReader(),
    larger: () => view?.zoomBy(1.25),
    smaller: () => view?.zoomBy(0.8),
  })

  onMount(() => {
    if (!element) return
    view = new ComicView(
      element,
      book.pages,
      {
        location: (place) => {
          setLocation(place)
          setScrub(undefined)
          if (!place.atEnd) setFinished(false)
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
        end: () => {
          setFinished(true)
          controls.show()
        },
      },
      { ...comicSettings(), direction: direction() },
      book.start,
    )
    element.focus({ preventScroll: true })
    onCleanup(() => {
      view?.destroy()
      book.release?.()
    })
  })

  const shownPage = () => scrub() ?? location()?.page ?? 0
  const pageLabel = () => {
    const place = location()
    if (!place) return ""
    const pages = scrub() === undefined ? place.pages : [shownPage()]
    const first = pages[0]! + 1
    const last = pages[pages.length - 1]! + 1
    return `${first === last ? `Page ${first}` : `Pages ${first}–${last}`} of ${place.count}`
  }

  return (
    <div
      class="relative h-full"
      onPointerMove={(event) => {
        if (event.pointerType === "mouse" && (event.movementX || event.movementY)) controls.moved()
      }}
    >
      <div ref={(node) => (element = node)} class="absolute inset-0" aria-label="Pages" />

      <TopBar controls={controls} title={book.title} subtitle={book.subtitle}>
        <Show when={(book.toc?.length ?? 0) > 0}>
          <Button
            variant="ghost"
            size="sm"
            class="size-10 px-0 [&_svg]:size-5"
            aria-label="Contents"
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
            <ToggleGroup
              label="Pages"
              value={comicSettings().flow}
              options={[
                { value: "automatic", label: "Automatic" },
                { value: "paged", label: "Turn" },
                { value: "scrolled", label: "Scroll" },
              ]}
              onChange={(flow) => {
                changeComicSettings({ flow })
                view?.setOptions({ flow })
              }}
            />
            <ToggleGroup
              label="Direction"
              value={direction()}
              options={[
                { value: "ltr", label: "Left to right" },
                { value: "rtl", label: "Right to left" },
              ]}
              onChange={(chosen) => {
                setSeriesDirection(book.seriesKey, chosen)
                view?.setOptions({ direction: chosen })
              }}
            />
            <ToggleGroup
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
            <p class="text-sm text-muted-foreground">
              Turn pages with the arrow keys, a swipe, or a click at either side. Double-click or
              press + and − to zoom.
            </p>
          </PopoverContent>
        </Popover>
      </TopBar>

      <Show when={finished() && next()}>{(after) => <UpNextCard next={after()} />}</Show>

      <PageButtons
        controls={controls}
        rtl={direction() === "rtl"}
        previous={() => view?.previous()}
        next={() => view?.next()}
      />

      <BottomBar controls={controls}>
        <Slider
          label="Page"
          value={shownPage()}
          minValue={0}
          maxValue={Math.max(count() - 1, 1)}
          inverted={direction() === "rtl"}
          getValueLabel={(value) => `Page ${value + 1} of ${count()}`}
          onChange={setScrub}
          onChangeEnd={(value) => view?.goTo(value)}
          disabled={count() < 2}
        />
        <p class="text-center text-[13px] text-muted-foreground tabular-nums" aria-live="polite">
          {pageLabel()}
        </p>
      </BottomBar>

      <ContentsDialog
        open={contents()}
        onOpenChange={(open) => {
          setContents(open)
          controls.hold("contents", open)
        }}
        items={book.toc ?? []}
        current={undefined}
        choose={(item) => {
          setContents(false)
          controls.hold("contents", false)
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
