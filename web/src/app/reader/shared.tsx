import { type JSX, Show, createSignal, onCleanup } from "solid-js"
import { useNavigate, useRouter } from "@tanstack/solid-router"
import { ChevronLeft } from "../../components/icons.tsx"
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

/** The bar over the top of the page: back, the title, and the reader's buttons. */
export function TopBar(props: {
  shown: boolean
  title: string
  subtitle?: string
  children?: JSX.Element
  class?: string
}) {
  const navigate = useNavigate()
  const router = useRouter()
  const close = () => {
    if (router.history.canGoBack()) router.history.back()
    else void navigate({ to: "/" })
  }
  return (
    <header
      class={cn(
        "absolute inset-x-0 top-0 z-10 flex items-center gap-2 border-b bg-background/85 px-2 pt-[calc(0.5rem+env(safe-area-inset-top))] pb-2 backdrop-blur-xl transition-[opacity,transform] duration-200 sm:px-4",
        !props.shown && "pointer-events-none -translate-y-2 opacity-0",
        props.class,
      )}
      aria-hidden={!props.shown}
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
export function BottomBar(props: { shown: boolean; children: JSX.Element; class?: string }) {
  return (
    <footer
      class={cn(
        "absolute inset-x-0 bottom-0 z-10 border-t bg-background/85 px-5 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] backdrop-blur-xl transition-[opacity,transform] duration-200",
        !props.shown && "pointer-events-none translate-y-2 opacity-0",
        props.class,
      )}
      aria-hidden={!props.shown}
    >
      <div class="mx-auto grid max-w-3xl gap-2.5">{props.children}</div>
    </footer>
  )
}

/** Offers what to read next, at the end. */
export function UpNextCard(props: { next: UpNext }) {
  return (
    <div class="absolute inset-x-0 bottom-28 z-10 flex justify-center px-4">
      <div class="flex max-w-md items-center gap-4 rounded-2xl border bg-card/95 p-4 shadow-xl backdrop-blur-xl">
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
