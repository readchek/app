import { Show, createEffect, createSignal, on, onCleanup, onMount } from "solid-js"
import { createResource } from "../../lib/resource.ts"
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
import { ContentsDialog } from "./Contents.tsx"
import { type BookSettings, bookSettings, changeBookSettings } from "./settings.ts"
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

/** A book to read: the opened file, and where to start and keep its place. */
export type BookSource = {
  account: Account
  title: string
  subtitle?: string
  publication: Publication
  start: Locator | null
  positions: Positions
  next: () => Promise<UpNext | undefined>
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
  const controls = createControls()
  const [finished, setFinished] = createSignal(false)
  const [contents, setContents] = createSignal(false)
  const [failure, setFailure] = createSignal<string>()
  const [systemDark, setSystemDark] = createSignal(dark.matches)
  const keeper = createKeeper(book.positions)
  const [next] = createResource(() => book.next())

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
    view = new BookView(
      element,
      book.publication,
      {
        location: (place) => {
          setLocation(place)
          setScrub(undefined)
          if (!place.atEnd) setFinished(false)
          keeper.keep(place.locator)
        },
        tap: () => controls.tap(),
        pointer: () => controls.moved(),
        end: () => {
          setFinished(true)
          controls.show()
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
      },
      book.start,
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
      class="relative h-full"
      style={{ background: background() }}
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
          </PopoverContent>
        </Popover>
      </TopBar>

      <Show when={failure()}>
        <div class="absolute inset-x-0 top-24 z-10 flex justify-center px-4">
          <p class="max-w-md rounded-2xl border bg-card p-4 text-[15px] shadow-xl">{failure()}</p>
        </div>
      </Show>

      <Show when={finished() && next()}>{(after) => <UpNextCard next={after()} />}</Show>

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
        <p class="flex justify-between gap-4 text-[13px] text-muted-foreground tabular-nums">
          <span class="min-w-0 truncate" aria-live="polite">
            {label()}
          </span>
          <span>{percent()}</span>
        </p>
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
