import { type JSX, Show, createEffect, createSignal, onCleanup } from "solid-js"
import { useNavigate, useRouter } from "@tanstack/solid-router"
import { ChevronLeft, ChevronRight } from "../../components/icons.tsx"
import { Button } from "../../components/ui/button.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../../components/ui/dialog.tsx"
import { cn } from "../../lib/cn.ts"
import { type Locator, type Progress, ProgressConflict } from "../client.ts"

// What the comic and book readers share: keeping the reader's place, the
// prompt when another device read on, the bars over the page, and what to
// read next.

/** Where a reader keeps its place: the server for a publication, this browser for a site chapter. */
export type Positions = {
  /** Keeps a place. Throws `ProgressConflict` when another device saved since. */
  save(locator: Locator): Promise<void>
  /** Takes another device's saved place as the one to save over next. */
  prefer(other: Progress): void
}

/** What comes after, offered at the end. */
export type UpNext = { title: string; open: () => void }

// Positions are saved a moment after the page settles, so flipping
// through a book saves once rather than for every page passed.
const saveDelay = 800

/**
 * Keeps the reader's place as it moves, and on leaving. When another
 * device saved a place since, `conflict` holds it until the reader picks.
 */
export function createKeeper(positions: Positions) {
  const [conflict, setConflict] = createSignal<Progress>()
  let pending: Locator | undefined
  let timer: ReturnType<typeof setTimeout> | undefined

  const save = async () => {
    clearTimeout(timer)
    const locator = pending
    pending = undefined
    if (!locator) return
    try {
      await positions.save(locator)
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

  const leave = () => void save()
  addEventListener("pagehide", leave)
  onCleanup(() => {
    removeEventListener("pagehide", leave)
    void save()
  })

  return {
    conflict,
    keep(locator: Locator) {
      pending = locator
      clearTimeout(timer)
      if (!conflict()) timer = setTimeout(() => void save(), saveDelay)
    },
    /** Keeps this device's place, saving it over the other device's. */
    keepMine() {
      const other = conflict()
      if (!other) return
      positions.prefer(other)
      setConflict(undefined)
      void save()
    },
    /** Takes the other device's place; the reader goes there. */
    takeTheirs(): Progress | undefined {
      const other = conflict()
      if (!other) return undefined
      positions.prefer(other)
      pending = undefined
      setConflict(undefined)
      return other
    },
  }
}

/** Asks which place to keep when another device read on. */
export function ConflictDialog(props: {
  keeper: ReturnType<typeof createKeeper>
  /** Where the other device is, such as "page 12". */
  place: (other: Progress) => string
  onTake: (other: Progress) => void
}) {
  return (
    <Dialog
      open={props.keeper.conflict() !== undefined}
      onOpenChange={(open) => {
        if (!open) props.keeper.keepMine()
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Read on another device</DialogTitle>
          <DialogDescription>
            {props.keeper.conflict()?.device ?? "Another device"} is at{" "}
            {props.keeper.conflict() ? props.place(props.keeper.conflict()!) : "another place"}. Go
            there, or keep reading here?
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => props.keeper.keepMine()}>
            Stay here
          </Button>
          <Button
            onClick={() => {
              const other = props.keeper.takeTheirs()
              if (other) props.onTake(other)
            }}
          >
            Go there
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/** Leaves the reader for where the person came from, or Reading Now when they opened it directly. */
export function useCloseReader(): () => void {
  const navigate = useNavigate()
  const router = useRouter()
  return () => {
    if (router.history.canGoBack()) router.history.back()
    else void navigate({ to: "/" })
  }
}

/** What the reader's keys do beyond turning pages: a book's text size, or a comic's zoom. */
export type ReaderKeys = { close(): void; larger?(): void; smaller?(): void }

/**
 * Escape closes the reader, and + and − make the page bigger or smaller. Returns
 * the handler for keys the book's page passes on, since its frame keeps
 * them from this document.
 */
export function createReaderKeys(keys: ReaderKeys): (key: string) => boolean {
  const press = (key: string) => {
    const action =
      key === "Escape"
        ? keys.close
        : key === "+" || key === "="
          ? keys.larger
          : key === "-" || key === "_"
            ? keys.smaller
            : undefined
    action?.()
    return action !== undefined
  }
  const keydown = (event: KeyboardEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (
      event.defaultPrevented ||
      event.metaKey ||
      event.ctrlKey ||
      event.altKey ||
      // Kobalte closes a dialog or popover on Escape without marking the
      // event, and focus is inside it while it's open.
      target?.closest("input, textarea, select, [contenteditable], [role=dialog], [role=menu]")
    )
      return
    if (press(event.key)) event.preventDefault()
  }
  addEventListener("keydown", keydown)
  onCleanup(() => removeEventListener("keydown", keydown))
  return press
}

// With a mouse, controls show while it moves and hide once it rests;
// long enough to reach a control, short enough not to sit over the page.
const hideDelay = 2500

const mouse = matchMedia("(hover: hover) and (pointer: fine)")

/** The reader's bars and buttons over the page: when they show, and what keeps them up. */
export type Controls = ReturnType<typeof createControls>

/**
 * Shows and hides the controls over the page. With a mouse, as on a
 * website, they follow the pointer: they show when it moves and hide when
 * it rests, unless it's over them or a control is in use. On a touch
 * screen a tap in the middle of the page shows or hides them, as in the
 * iOS app.
 */
export function createControls() {
  const [hovering, setHovering] = createSignal(mouse.matches)
  const [shown, setShown] = createSignal(true)
  const holds = new Set<string>()
  let timer: ReturnType<typeof setTimeout> | undefined

  const schedule = () => {
    clearTimeout(timer)
    if (hovering() && holds.size === 0) timer = setTimeout(() => setShown(false), hideDelay)
  }
  const show = () => {
    setShown(true)
    schedule()
  }
  const followDevice = (event: MediaQueryListEvent) => {
    setHovering(event.matches)
    show()
  }
  mouse.addEventListener("change", followDevice)
  // Tab reaches the controls even while they're hidden, and they stay up
  // while the keyboard moves the slider. Other keys read on.
  const keydown = (event: KeyboardEvent) => {
    if (event.key === "Tab" || document.activeElement?.closest("[role=slider]")) show()
  }
  addEventListener("keydown", keydown, true)
  onCleanup(() => {
    clearTimeout(timer)
    mouse.removeEventListener("change", followDevice)
    removeEventListener("keydown", keydown, true)
  })
  // They start shown, so the reader sees where they are, then get out of the way.
  schedule()

  const hold = (reason: string, held: boolean) => {
    if (held) holds.add(reason)
    else holds.delete(reason)
    if (held) setShown(true)
    schedule()
  }

  return {
    shown,
    /** Whether a mouse drives the controls rather than taps. */
    hovering,
    show,
    hide() {
      clearTimeout(timer)
      setShown(false)
    },
    /** The mouse moved over the page. */
    moved() {
      if (hovering()) show()
    },
    /** A tap in the middle of the page, which shows or hides the controls on a touch screen. */
    tap() {
      if (!hovering()) setShown((now) => !now)
    },
    /** Keeps the controls up while `held`, such as while a menu is open. */
    hold,
    /** Keeps the controls up while the mouse is over `element` or presses it, such as a bar. */
    watch(element: HTMLElement, name: string) {
      element.addEventListener("pointerenter", (event) => {
        if (event.pointerType === "mouse") hold(`${name} pointer`, true)
      })
      element.addEventListener("pointerleave", (event) => {
        if (event.pointerType === "mouse") hold(`${name} pointer`, false)
      })
      // Captured, since the slider's thumb stops its pointer events.
      element.addEventListener(
        "pointerdown",
        () => {
          hold(`${name} press`, true)
          const release = () => {
            hold(`${name} press`, false)
            // The slider focuses its thumb as a drag ends, and would then take
            // the arrow keys, which turn pages everywhere else. Tabbing to it
            // keeps them.
            setTimeout(() => {
              const focused = document.activeElement
              if (focused instanceof HTMLElement && element.contains(focused)) {
                if (focused.closest("[role=slider]")) focused.blur()
              }
            })
          }
          addEventListener("pointerup", release, { once: true, capture: true })
        },
        true,
      )
    },
  }
}

/**
 * Ties something over the page to the controls: it stays up while used,
 * and lets go of focus once hidden. Returns the ref for its element.
 */
function useControl(controls: Controls, name: string): (element: HTMLElement) => void {
  let element: HTMLElement | undefined
  createEffect(() => {
    if (controls.shown()) return
    // Focus left on a hidden control would take keys from the page.
    const focused = document.activeElement
    if (focused instanceof HTMLElement && element?.contains(focused)) focused.blur()
  })
  return (node) => {
    element = node
    controls.watch(node, name)
  }
}

/** The bar over the top of the page: back, the title, and the reader's buttons. */
export function TopBar(props: {
  controls: Controls
  title: string
  subtitle?: string
  children?: JSX.Element
  class?: string
}) {
  const close = useCloseReader()
  const ref = useControl(props.controls, "top")
  return (
    <header
      ref={ref}
      class={cn(
        "absolute inset-x-0 top-0 z-10 flex items-center gap-2 border-b bg-background/95 px-2 pt-[calc(0.5rem+env(safe-area-inset-top))] pb-2 transition-[opacity,transform] duration-200 sm:px-4",
        !props.controls.shown() && "pointer-events-none -translate-y-2 opacity-0",
        props.class,
      )}
      inert={!props.controls.shown()}
    >
      <Button
        variant="ghost"
        size="sm"
        class="size-10 px-0 [&_svg]:size-5"
        aria-label="Close"
        aria-keyshortcuts="Escape"
        onClick={close}
      >
        <ChevronLeft />
      </Button>
      <div class="min-w-0 flex-1 text-center">
        <p class="truncate text-[15px] font-semibold">{props.title}</p>
        <Show when={props.subtitle}>
          <p class="truncate text-[13px] text-muted-foreground">{props.subtitle}</p>
        </Show>
      </div>
      <div class="flex items-center">{props.children}</div>
    </header>
  )
}

/** The bar along the bottom of the page. */
export function BottomBar(props: { controls: Controls; children: JSX.Element; class?: string }) {
  const ref = useControl(props.controls, "bottom")
  return (
    <footer
      ref={ref}
      class={cn(
        "absolute inset-x-0 bottom-0 z-10 border-t bg-background/95 px-5 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] transition-[opacity,transform] duration-200",
        !props.controls.shown() && "pointer-events-none translate-y-2 opacity-0",
        props.class,
      )}
      inert={!props.controls.shown()}
    >
      <div class="mx-auto grid max-w-3xl gap-2.5">{props.children}</div>
    </footer>
  )
}

/**
 * Page turn buttons at either side of the page, for a mouse. They show and
 * hide with the controls; touch screens turn pages with taps and swipes.
 */
export function PageButtons(props: {
  controls: Controls
  /** Whether forward is toward the left, as in a right-to-left book. */
  rtl: boolean
  previous: () => void
  next: () => void
}) {
  const side = (left: boolean) => {
    const ref = useControl(props.controls, left ? "left" : "right")
    const forward = () => left === props.rtl
    return (
      <Button
        ref={ref}
        variant="outline"
        size="sm"
        class={cn(
          "absolute top-1/2 z-10 size-10 -translate-y-1/2 px-0 transition-opacity duration-200 [&_svg]:size-5",
          left ? "left-2" : "right-2",
          !props.controls.shown() && "pointer-events-none opacity-0",
        )}
        aria-label={forward() ? "Next page" : "Previous page"}
        inert={!props.controls.shown()}
        onClick={() => (forward() ? props.next() : props.previous())}
      >
        {left ? <ChevronLeft /> : <ChevronRight />}
      </Button>
    )
  }
  return (
    <Show when={props.controls.hovering()}>
      {side(true)}
      {side(false)}
    </Show>
  )
}

/** Offers what to read next, at the end. */
export function UpNextCard(props: { next: UpNext }) {
  return (
    <div class="absolute inset-x-0 bottom-28 z-10 flex justify-center px-4">
      <div class="flex max-w-md items-center gap-4 rounded-2xl border bg-card p-4 shadow-xl">
        <p class="min-w-0 text-[15px]">
          <span class="block text-muted-foreground">Up next</span>
          <span class="block truncate font-semibold">{props.next.title}</span>
        </p>
        <Button size="sm" onClick={() => props.next.open()}>
          Read
        </Button>
      </div>
    </div>
  )
}
