import { Show, createResource, createSignal, onCleanup, onMount } from "solid-js"
import { useNavigate, useRouter } from "@tanstack/solid-router"
import {
  type ComicLocation,
  ComicView,
  type Locator,
  type ReadingDirection,
  comicPageIndex,
} from "@readchek/reader"
import { ChevronLeft, Sliders } from "../../components/icons.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../../components/ui/dialog.tsx"
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
import { type Progress, ProgressConflict } from "../client.ts"
import { loadImage } from "../images.ts"
import {
  changeComicSettings,
  comicSettings,
  seriesDirection,
  setSeriesDirection,
} from "./settings.ts"

// Positions are saved a moment after the page settles, so flipping
// through a book saves once rather than for every page passed.
const saveDelay = 800

/** Where a reader keeps its place: the server for a publication, this browser for a site chapter. */
export type Positions = {
  /** Keeps a place. Throws `ProgressConflict` when another device saved since. */
  save(locator: Locator): Promise<void>
  /** Takes another device's saved place as the one to save over next. */
  prefer(other: Progress): void
}

/** What comes after the comic, offered at its end. */
export type UpNext = { title: string; open: () => void }

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
  const navigate = useNavigate()
  const router = useRouter()
  let element: HTMLDivElement | undefined
  let view: ComicView | undefined

  const book = props.book
  const direction = (): ReadingDirection =>
    seriesDirection(book.seriesKey) ?? book.direction ?? "ltr"

  const [location, setLocation] = createSignal<ComicLocation>()
  const [scrub, setScrub] = createSignal<number>()
  const [controls, setControls] = createSignal(true)
  const [finished, setFinished] = createSignal(false)
  const [conflict, setConflict] = createSignal<Progress>()

  // The place waiting to be written.
  let pending: Locator | undefined
  let timer: ReturnType<typeof setTimeout> | undefined

  const save = async () => {
    clearTimeout(timer)
    const locator = pending
    pending = undefined
    if (!locator) return
    try {
      await book.positions.save(locator)
    } catch (error) {
      if (error instanceof ProgressConflict) {
        // Another device read on. The reader picks which place to keep.
        pending = locator
        setConflict(error.current)
      }
      // Anything else, such as being offline, waits for the next page turn.
      else pending ??= locator
    }
  }

  const keep = (locator: Locator) => {
    pending = locator
    clearTimeout(timer)
    if (!conflict()) timer = setTimeout(() => void save(), saveDelay)
  }

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
          keep(locator)
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
    const leave = () => void save()
    addEventListener("pagehide", leave)
    onCleanup(() => {
      removeEventListener("pagehide", leave)
      void save()
      view?.destroy()
    })
  })

  const close = () => {
    if (router.history.canGoBack()) router.history.back()
    else void navigate({ to: "/" })
  }

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

      <header
        class={cn(
          "absolute inset-x-0 top-0 z-10 flex items-center gap-2 border-b bg-background/85 px-2 pt-[calc(0.5rem+env(safe-area-inset-top))] pb-2 backdrop-blur-xl transition-[opacity,transform] duration-200 sm:px-4",
          !controls() && "pointer-events-none -translate-y-2 opacity-0",
        )}
        aria-hidden={!controls()}
      >
        <Button
          variant="ghost"
          size="sm"
          class="size-10 px-0 [&_svg]:size-5"
          aria-label="Close"
          onClick={close}
        >
          <ChevronLeft />
        </Button>
        <div class="min-w-0 flex-1 text-center">
          <p class="truncate text-[15px] font-semibold">{book.title}</p>
          <Show when={book.subtitle}>
            <p class="truncate text-[13px] text-muted-foreground">{book.subtitle}</p>
          </Show>
        </div>
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
      </header>

      <Show when={finished() && next()}>
        {(after) => (
          <div class="absolute inset-x-0 bottom-28 z-10 flex justify-center px-4">
            <div class="flex max-w-md items-center gap-4 rounded-2xl border bg-card/95 p-4 shadow-xl backdrop-blur-xl">
              <p class="min-w-0 text-[15px]">
                <span class="block text-muted-foreground">Up next</span>
                <span class="block truncate font-semibold">{after().title}</span>
              </p>
              <Button size="sm" onClick={() => after().open()}>
                Read
              </Button>
            </div>
          </div>
        )}
      </Show>

      <footer
        class={cn(
          "absolute inset-x-0 bottom-0 z-10 border-t bg-background/85 px-5 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] backdrop-blur-xl transition-[opacity,transform] duration-200",
          !controls() && "pointer-events-none translate-y-2 opacity-0",
        )}
        aria-hidden={!controls()}
      >
        <div class="mx-auto grid max-w-3xl gap-2.5">
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
        </div>
      </footer>

      <Dialog
        open={conflict() !== undefined}
        onOpenChange={(open) => {
          if (!open) keepThisPage()
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Read on another device</DialogTitle>
            <DialogDescription>
              {conflict()?.device ?? "Another device"} is at {otherPlace()}. Go there, or keep
              reading here?
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={keepThisPage}>
              Stay here
            </Button>
            <Button onClick={goToOther}>Go there</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )

  function otherPlace(): string {
    const index = comicPageIndex(conflict()?.locator, book.pages.length)
    return index === undefined ? "another place" : `page ${index + 1}`
  }

  // Keeps this device's place: saves it over the other device's.
  function keepThisPage() {
    const other = conflict()
    if (!other) return
    book.positions.prefer(other)
    setConflict(undefined)
    void save()
  }

  function goToOther() {
    const other = conflict()
    if (!other) return
    book.positions.prefer(other)
    pending = undefined
    setConflict(undefined)
    const index = comicPageIndex(other.locator, book.pages.length)
    if (index !== undefined) view?.goTo(index)
  }
}
