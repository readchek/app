import { Show, createResource, createSignal, onCleanup, onMount } from "solid-js"
import {
  type ComicLocation,
  ComicView,
  type Locator,
  type ReadingDirection,
  comicPageIndex,
} from "@readchek/reader"
import { Sliders } from "../../components/icons.tsx"
import { buttonVariants } from "../../components/ui/button.tsx"
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
import {
  changeComicSettings,
  comicSettings,
  seriesDirection,
  setSeriesDirection,
} from "./settings.ts"
import {
  BottomBar,
  ConflictDialog,
  type Positions,
  TopBar,
  type UpNext,
  UpNextCard,
  createKeeper,
} from "./shared.tsx"

/** A comic to read: its pages as paths on the account's server, and where to start and keep its place. */
export type ComicBook = {
  account: Account
  title: string
  subtitle?: string
  pages: string[]
  start: Locator | null
  /** Names the series for its chosen reading direction, with its server. */
  seriesKey: string
  direction: ReadingDirection | null
  positions: Positions
  next: () => Promise<UpNext | undefined>
}

/** A comic open full screen: the pages, and controls that appear on a tap in the middle. */
export function ComicReader(props: { book: ComicBook }) {
  let element: HTMLDivElement | undefined
  let view: ComicView | undefined

  const book = props.book
  const direction = (): ReadingDirection =>
    seriesDirection(book.seriesKey) ?? book.direction ?? "ltr"

  const [location, setLocation] = createSignal<ComicLocation>()
  const [scrub, setScrub] = createSignal<number>()
  const [controls, setControls] = createSignal(true)
  const [finished, setFinished] = createSignal(false)
  const keeper = createKeeper(book.positions)
  const [next] = createResource(() => book.next())

  onMount(() => {
    if (!element) return
    view = new ComicView(
      element,
      {
        count: book.pages.length,
        load: (index) => loadImage(book.account, book.pages[index]!),
      },
      {
        location: (place) => {
          setLocation(place)
          setScrub(undefined)
          if (!place.atEnd) setFinished(false)
          // The server counts a book finished only at 1, and a comic's
          // last page starts short of it, so reaching it says so outright.
          const locator = place.atEnd
            ? { ...place.locator, locations: { ...place.locator.locations, totalProgression: 1 } }
            : place.locator
          keeper.keep(locator)
        },
        tap: () => setControls((shown) => !shown),
        end: () => {
          setFinished(true)
          setControls(true)
        },
      },
      { ...comicSettings(), direction: direction() },
      book.start,
    )
    element.focus({ preventScroll: true })
    onCleanup(() => view?.destroy())
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
    <div class="relative h-full">
      <div ref={(node) => (element = node)} class="absolute inset-0" aria-label="Pages" />

      <TopBar shown={controls()} title={book.title} subtitle={book.subtitle}>
        <Popover placement="bottom-end" gutter={8}>
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
              Turn pages with the arrow keys, a swipe, or a click at either side. Double-click to
              zoom.
            </p>
          </PopoverContent>
        </Popover>
      </TopBar>

      <Show when={finished() && next()}>{(after) => <UpNextCard next={after()} />}</Show>

      <BottomBar shown={controls()}>
        <Slider
          label="Page"
          value={shownPage()}
          minValue={0}
          maxValue={Math.max(book.pages.length - 1, 1)}
          inverted={direction() === "rtl"}
          getValueLabel={(value) => `Page ${value + 1} of ${book.pages.length}`}
          onChange={setScrub}
          onChangeEnd={(value) => view?.goTo(value)}
          disabled={book.pages.length < 2}
        />
        <p class="text-center text-[13px] text-muted-foreground tabular-nums" aria-live="polite">
          {pageLabel()}
        </p>
      </BottomBar>

      <ConflictDialog
        keeper={keeper}
        place={(other) => {
          const index = comicPageIndex(other.locator, book.pages.length)
          return index === undefined ? "another place" : `page ${index + 1}`
        }}
        onTake={(other) => {
          const index = comicPageIndex(other.locator, book.pages.length)
          if (index !== undefined) view?.goTo(index)
        }}
      />
    </div>
  )
}
