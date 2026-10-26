import {
  For,
  type JSX,
  Show,
  createEffect,
  createResource,
  createSignal,
  on,
  onCleanup,
  onMount,
} from "solid-js"
import {
  type BookLocation,
  type BookPreferences,
  BookView,
  type Epub,
  type Locator,
  type TocItem,
} from "@readchek/reader"
import { ListBullet, Minus, Plus, Sliders } from "../../components/icons.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "../../components/ui/dialog.tsx"
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
import { type BookSettings, bookSettings, changeBookSettings } from "./settings.ts"
import {
  BottomBar,
  ConflictDialog,
  type Positions,
  TopBar,
  type UpNext,
  UpNextCard,
  createKeeper,
} from "./shared.tsx"

/** A book to read: the opened file, and where to start and keep its place. */
export type BookSource = {
  account: Account
  title: string
  subtitle?: string
  epub: Epub
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

/** A book open full screen, paged like the iOS app's, with contents, settings and a place kept as you read. */
export function BookReader(props: { book: BookSource }) {
  let element: HTMLDivElement | undefined
  let view: BookView | undefined
  const book = props.book

  const [location, setLocation] = createSignal<BookLocation>()
  const [scrub, setScrub] = createSignal<number>()
  const [controls, setControls] = createSignal(true)
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

  onMount(() => {
    if (!element) return
    view = new BookView(
      element,
      book.epub,
      {
        location: (place) => {
          setLocation(place)
          setScrub(undefined)
          if (!place.atEnd) setFinished(false)
          keeper.keep(place.locator)
        },
        tap: () => setControls((shown) => !shown),
        end: () => {
          setFinished(true)
          setControls(true)
        },
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

  const total = () => location()?.positionCount ?? book.epub.positionCount
  const shownPosition = () => scrub() ?? location()?.position ?? 1
  const label = () => {
    const place = location()
    if (!place) return ""
    if (scrub() !== undefined) return `Position ${shownPosition()} of ${total()}`
    const page = `Page ${place.page + 1} of ${place.pageCount}`
    return place.chapter ? `${place.chapter.title} · ${page}` : page
  }
  const percent = () => {
    const progress = location()?.locator.locations?.totalProgression ?? 0
    return `${Math.round(progress * 100)}%`
  }

  const size = () => bookSettings().fontScale
  const resize = (step: 1 | -1) => {
    const index = sizes.findIndex((value) => value >= size() - 0.001)
    const nextIndex = Math.min(Math.max((index < 0 ? 2 : index) + step, 0), sizes.length - 1)
    changeBookSettings({ fontScale: sizes[nextIndex]! })
  }

  return (
    <div class="relative h-full" style={{ background: background() }}>
      <div ref={(node) => (element = node)} class="absolute inset-0" aria-label="Book" />

      <TopBar
        shown={controls()}
        title={book.title}
        subtitle={location()?.chapter?.title ?? book.subtitle}
      >
        <Show when={book.epub.toc.length > 0}>
          <Button
            variant="ghost"
            size="sm"
            class="size-10 px-0 [&_svg]:size-5"
            aria-label="Contents"
            onClick={() => setContents(true)}
          >
            <ListBullet />
          </Button>
        </Show>
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
                  disabled={size() >= sizes[sizes.length - 1]!}
                  onClick={() => resize(1)}
                >
                  <Plus />
                </Button>
              </div>
            </div>
            <ToggleGroup
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
            <ToggleGroup
              label="Font"
              value={bookSettings().font}
              options={[
                { value: "default", label: "Book's" },
                { value: "serif", label: "Serif" },
                { value: "sans", label: "Sans serif" },
              ]}
              onChange={(font) => changeBookSettings({ font })}
            />
            <ToggleGroup
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
            <ToggleGroup
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
          <p class="max-w-md rounded-2xl border bg-card/95 p-4 text-[15px] shadow-xl backdrop-blur-xl">
            {failure()}
          </p>
        </div>
      </Show>

      <Show when={finished() && next()}>{(after) => <UpNextCard next={after()} />}</Show>

      <BottomBar shown={controls()}>
        <Slider
          label="Place in the book"
          value={shownPosition()}
          minValue={1}
          maxValue={Math.max(total(), 2)}
          inverted={book.epub.metadata.readingProgression === "rtl"}
          getValueLabel={(value) => `Position ${value} of ${total()}`}
          onChange={setScrub}
          onChangeEnd={(value) => void view?.goToProgression((value - 1) / total())}
          disabled={total() < 2}
        />
        <p class="flex justify-between gap-4 text-[13px] text-muted-foreground tabular-nums">
          <span class="min-w-0 truncate" aria-live="polite">
            {label()}
          </span>
          <span>{percent()}</span>
        </p>
      </BottomBar>

      <Dialog open={contents()} onOpenChange={setContents}>
        <DialogContent class="max-w-xl">
          <DialogHeader>
            <DialogTitle>Contents</DialogTitle>
          </DialogHeader>
          <nav aria-label="Contents" class="-mx-2">
            <TocList
              items={book.epub.toc}
              current={location()?.chapter}
              depth={0}
              choose={(item) => {
                setContents(false)
                void view?.goToHref(item.href)
                setControls(false)
              }}
            />
          </nav>
        </DialogContent>
      </Dialog>

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

function TocList(props: {
  items: TocItem[]
  current: TocItem | undefined
  depth: number
  choose: (item: TocItem) => void
}): JSX.Element {
  return (
    <ul class={cn(props.depth > 0 && "ms-4")}>
      <For each={props.items}>
        {(item) => (
          <li>
            <button
              type="button"
              class={cn(
                "w-full rounded-lg px-2 py-2.5 text-start text-[15px] transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none",
                props.current === item && "font-semibold text-link",
              )}
              aria-current={props.current === item ? "location" : undefined}
              onClick={() => props.choose(item)}
            >
              {item.title}
            </button>
            <Show when={item.children.length > 0}>
              <TocList
                items={item.children}
                current={props.current}
                depth={props.depth + 1}
                choose={props.choose}
              />
            </Show>
          </li>
        )}
      </For>
    </ul>
  )
}
