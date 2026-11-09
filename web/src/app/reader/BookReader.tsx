import { Show, createEffect, createSignal, on, onCleanup, onMount } from "solid-js"
import { Portal } from "solid-js/web"
import {
  type BookLocation,
  type BookPreferences,
  BookView,
  type Locator,
  type Publication,
  type TocItem,
} from "@readchek/reader"
import { ListBullet, Minus, Plus, Sliders } from "../../components/icons.tsx"
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
import { ChapterEndPage, ChapterStartPage } from "./ChapterEnd.tsx"
import { ContentsDialog } from "./Contents.tsx"
import { type BookSettings, bookSettings, changeBookSettings } from "./settings.ts"
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

/** A book to read: the opened file, and where to start and keep its place. */
export type BookSource = {
  account: Account
  title: string
  subtitle?: string
  publication: Publication
  start: Locator | null
  positions: Positions
  /** What's either side of it, when it's one of a series. */
  neighbors?: Neighbors
  /** Where readers' comments on it come from, for a chapter from a site that has them. */
  comments?: CommentSource
}

// The page behind the book's own, for each theme. They match the reader
// script's themes, so the frame's edges don't show.
const backgrounds: Record<Exclude<BookPreferences["theme"], "default">, string> = {
  light: "#ffffff",
  sepia: "#f5ecd9",
  dark: "#121212",
}

const sizes = [0.8, 0.9, 1, 1.1, 1.25, 1.4, 1.6, 1.8, 2]

const dark = matchMedia("(prefers-color-scheme: dark)")

/** The title of the entry each contents entry is inside, such as a chapter's part. */
function parentTitles(items: TocItem[], parent?: string, found = new Map<TocItem, string>()) {
  for (const item of items) {
    if (parent) found.set(item, parent)
    parentTitles(item.children, item.title, found)
  }
  return found
}

/** A book open full screen, paged like the iOS app's, with contents, settings and a place kept as you read. */
export function BookReader(props: { book: BookSource }) {
  let element: HTMLDivElement | undefined
  let view: BookView | undefined
  const book = props.book

  const [location, setLocation] = createSignal<BookLocation>()
  const [scrub, setScrub] = createSignal<number>()
  const neighbors = book.neighbors
  // Read into from the book before or after, or opened from a list.
  const arrival = takeArrival()
  // Reading into a book comes without the controls: nobody asked for them.
  const controls = createControls({ hidden: arrival !== undefined })
  const comments = book.comments && createComments(book.comments)
  const [leaving, setLeaving] = createSignal<"before" | "after">()
  const [contents, setContents] = createSignal(false)
  const [failure, setFailure] = createSignal<string>()
  const [systemDark, setSystemDark] = createSignal(dark.matches)
  const keeper = createKeeper(book.positions)

  /** Opens the book either side, saying how it was reached. */
  const go = (neighbor: Neighbor, from?: "start" | "end") => {
    if (leaving()) return
    setLeaving(neighbor === neighbors?.previous ? "before" : "after")
    arriveBy(from)
    neighbor.open(from)
  }

  // The pages either side of the book: one element each, placed by the
  // view over the page and drawn here.
  const ends = {
    before: neighbors?.previous ? document.createElement("div") : undefined,
    after: neighbors ? document.createElement("div") : undefined,
  }
  for (const end of [ends.before, ends.after]) end?.style.setProperty("height", "100%")

  const followSystem = (event: MediaQueryListEvent) => setSystemDark(event.matches)
  dark.addEventListener("change", followSystem)
  onCleanup(() => dark.removeEventListener("change", followSystem))

  const preferences = (settings: BookSettings = bookSettings()): BookPreferences => ({
    ...settings,
    theme: settings.theme === "automatic" ? (systemDark() ? "dark" : "light") : settings.theme,
  })
  const background = () => {
    const theme = preferences().theme
    return theme === "default" ? undefined : backgrounds[theme]
  }

  const size = () => bookSettings().fontScale
  const resize = (step: 1 | -1) => {
    const index = sizes.findIndex((value) => value >= size() - 0.001)
    const nextIndex = Math.min(Math.max((index < 0 ? 2 : index) + step, 0), sizes.length - 1)
    changeBookSettings({ fontScale: sizes[nextIndex]! })
  }
  const pressKey = createReaderKeys({
    close: useCloseReader(),
    larger: () => resize(1),
    smaller: () => resize(-1),
  })
  const rtl = book.publication.metadata.readingProgression === "rtl"

  onMount(() => {
    if (!element) return
    let lastPage: number | undefined
    let prepared = false
    // A book finished before starts over, since its last page is no
    // place to pick it up again.
    const finishedBefore = (book.start?.locations?.totalProgression ?? 0) >= 1
    const order = book.publication.readingOrder
    const last = order[order.length - 1]
    const start: Locator | null =
      arrival === "end" && last
        ? { href: last.href, type: last.type, locations: { progression: 1 } }
        : arrival === "start" || finishedBefore
          ? null
          : book.start
    view = new BookView(
      element,
      book.publication,
      {
        location: (place) => {
          setLocation(place)
          setScrub(undefined)
          if (lastPage !== undefined && lastPage !== place.position) controls.read()
          lastPage = place.position
          if (place.atEnd && !prepared) {
            prepared = true
            neighbors?.next?.prepare?.()
          }
          keeper.keep(place.locator)
        },
        tap: () => controls.tap(),
        pointer: () => controls.moved(),
        leave: (toward) => {
          const neighbor = toward === "after" ? neighbors?.next : neighbors?.previous
          if (neighbor) go(neighbor, toward === "after" ? "start" : "end")
        },
        // Tab moves focus within the page's frame too, toward the controls.
        key: (key) => (key === "Tab" ? controls.show() : void pressKey(key)),
        externalLink: (url) => {
          if (/^https?:/i.test(url)) open(url, "_blank", "noopener,noreferrer")
        },
        error: (error) =>
          setFailure(
            error instanceof Error ? error.message : "This part of the book couldn't be shown.",
          ),
      },
      {
        frameUrl: `${import.meta.env.BASE_URL}reader-frame/frame.html`,
        preferences: preferences(),
        ends,
      },
      start,
    )
    element.focus({ preventScroll: true })
    onCleanup(() => view?.destroy())
  })

  // Settings, and the system's look for the automatic theme, apply as they change.
  createEffect(
    on(
      () => preferences(),
      (chosen) => void view?.setPreferences(chosen),
      { defer: true },
    ),
  )

  const total = () => location()?.positionCount ?? book.publication.positionCount
  const shownPosition = () => scrub() ?? location()?.position ?? 1
  const label = () => {
    const place = location()
    if (!place) return ""
    if (scrub() !== undefined) return scrubLabel(shownPosition())
    if (place.edge === "after") return "Finished"
    const page = `Page ${place.page + 1} of ${place.pageCount}`
    return place.chapter ? `${place.chapter.title} · ${page}` : page
  }
  const progressionOf = (position: number) => (position - 1) / total()
  const parents = parentTitles(book.publication.toc)
  // While dragging, where the book would open: the chapter, with the part
  // it's in, since many books number chapters again in each part.
  const scrubLabel = (position: number) => {
    const chapter = view?.chapterAt(progressionOf(position))
    if (!chapter) return `Position ${position} of ${total()}`
    const parent = parents.get(chapter)
    return parent ? `${parent} · ${chapter.title}` : chapter.title
  }
  const percent = () => {
    const progress =
      scrub() === undefined
        ? (location()?.locator.locations?.totalProgression ?? 0)
        : progressionOf(shownPosition())
    return `${Math.round(progress * 100)}%`
  }

  return (
    <div
      ref={(node) => arrival && settleWheel(node)}
      class="relative h-full transition-[margin] duration-200"
      // The page makes room for the comments beside it rather than going under them.
      style={{
        background: background(),
        "margin-right": isDocked(comments) ? `${PANEL_WIDTH}px` : "0",
      }}
      onPointerMove={(event) => {
        if (event.pointerType === "mouse" && (event.movementX || event.movementY)) controls.moved()
      }}
    >
      <div ref={(node) => (element = node)} class="absolute inset-0" aria-label="Book" />

      <TopBar
        controls={controls}
        title={book.title}
        subtitle={location()?.chapter?.title ?? book.subtitle}
      >
        <Show when={comments}>{(shown) => <CommentsButton comments={shown()} />}</Show>
        <Show when={book.publication.toc.length > 0}>
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
          <PopoverContent class="grid w-80 gap-5">
            <PopoverTitle>Reading settings</PopoverTitle>
            <div class="grid gap-2">
              <span class="text-sm font-semibold">Text size</span>
              <div class="flex items-center justify-between gap-3 rounded-xl bg-muted p-1">
                <Button
                  variant="ghost"
                  size="sm"
                  class="size-9 px-0"
                  aria-label="Smaller text"
                  aria-keyshortcuts="-"
                  disabled={size() <= sizes[0]!}
                  onClick={() => resize(-1)}
                >
                  <Minus />
                </Button>
                <span class="text-sm font-semibold tabular-nums">{Math.round(size() * 100)}%</span>
                <Button
                  variant="ghost"
                  size="sm"
                  class="size-9 px-0"
                  aria-label="Larger text"
                  aria-keyshortcuts="+"
                  disabled={size() >= sizes[sizes.length - 1]!}
                  onClick={() => resize(1)}
                >
                  <Plus />
                </Button>
              </div>
            </div>
            <Choice
              label="Theme"
              value={bookSettings().theme}
              options={[
                { value: "automatic", label: "Auto" },
                { value: "light", label: "Light" },
                { value: "sepia", label: "Sepia" },
                { value: "dark", label: "Dark" },
              ]}
              onChange={(theme) => changeBookSettings({ theme })}
            />
            <Choice
              label="Font"
              value={bookSettings().font}
              options={[
                { value: "default", label: "Book's" },
                { value: "serif", label: "Serif" },
                { value: "sans", label: "Sans serif" },
              ]}
              onChange={(font) => changeBookSettings({ font })}
            />
            <Choice
              label="Line spacing"
              value={String(bookSettings().lineHeight)}
              options={[
                { value: "0", label: "Book's" },
                { value: "1.4", label: "Tight" },
                { value: "1.65", label: "Roomy" },
                { value: "1.9", label: "Airy" },
              ]}
              onChange={(value) => changeBookSettings({ lineHeight: Number(value) })}
            />
            <Choice
              label="Margins"
              value={String(bookSettings().marginScale)}
              options={[
                { value: "0.5", label: "Narrow" },
                { value: "1", label: "Normal" },
                { value: "1.75", label: "Wide" },
              ]}
              onChange={(value) => changeBookSettings({ marginScale: Number(value) })}
            />
            <Show when={book.comments}>{(source) => <CommentSettings source={source()} />}</Show>
          </PopoverContent>
        </Popover>
      </TopBar>

      <Show when={failure()}>
        <div class="absolute inset-x-0 top-24 z-10 flex justify-center px-4">
          <p class="max-w-md rounded-2xl border bg-card p-4 text-[15px] shadow-xl">{failure()}</p>
        </div>
      </Show>

      <Show when={neighbors && ends.after}>
        <Portal mount={ends.after} ref={(node) => (node.style.height = "100%")}>
          <ChapterEndPage
            finished={book.title}
            neighbors={neighbors!}
            motion="turn"
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
              motion="turn"
              opening={leaving() === "before"}
              go={(neighbor) => go(neighbor, "end")}
            />
          </Portal>
        )}
      </Show>
      <Show when={comments}>{(shown) => <CommentsPanel comments={shown()} />}</Show>

      <PageButtons
        controls={controls}
        rtl={rtl}
        previous={() => void view?.previous()}
        next={() => void view?.next()}
      />

      <BottomBar controls={controls}>
        <Slider
          class="flex-row"
          value={[shownPosition()]}
          minValue={1}
          maxValue={Math.max(total(), 2)}
          inverted={rtl}
          getValueLabel={(params) => scrubLabel(params.values[0]!)}
          onChange={(values) => setScrub(values[0]!)}
          onChangeEnd={(values) => void view?.goToProgression(progressionOf(values[0]!))}
          disabled={total() < 2}
        >
          <SliderLabel class="sr-only">Place in the book</SliderLabel>
          <SliderTrack>
            <SliderFill />
            <SliderThumb />
          </SliderTrack>
        </Slider>
        <ChapterButtons neighbors={neighbors} rtl={rtl} go={(neighbor) => go(neighbor)}>
          <p class="flex min-w-0 justify-center gap-3 text-[13px] text-muted-foreground tabular-nums">
            <span class="min-w-0 truncate" aria-live="polite">
              {label()}
            </span>
            <span>{percent()}</span>
          </p>
        </ChapterButtons>
      </BottomBar>

      <ContentsDialog
        open={contents()}
        onOpenChange={(open) => {
          setContents(open)
          controls.hold("contents", open)
        }}
        items={book.publication.toc}
        current={location()?.chapter}
        choose={(item) => {
          setContents(false)
          controls.hold("contents", false)
          void view?.goToHref(item.href)
          controls.hide()
        }}
      />

      <ConflictDialog
        keeper={keeper}
        place={(other) => {
          const progress = other.locator?.locations?.totalProgression
          return progress === undefined ? "another place" : `${Math.round(progress * 100)}%`
        }}
        onTake={(other) => {
          if (other.locator) void view?.goTo(other.locator)
        }}
      />
    </div>
  )
}
