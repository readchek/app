import { type JSX, Match, Show, Switch } from "solid-js"
import { Spinner } from "../../components/icons.tsx"
import type { Neighbor, Neighbors } from "./shared.tsx"

// What's between one chapter and the next: a page of plain type in the
// flow of reading, one turn after the last page and one before the first.
// The same turn or scroll that brought you here goes on through it, and
// going back returns to the page you came from. Every book and comic
// ends this way, so there's one thing to learn.

/** How the pages move, which is what the hint names. */
export type Motion = "turn" | "scroll"

function Entry(props: { label: string; title: string; neighbor?: Neighbor; go?: () => void }) {
  const text = (
    <>
      <span class="block text-[13px] text-muted-foreground">{props.label}</span>
      <span class="mt-0.5 block text-xl leading-snug font-semibold [overflow-wrap:anywhere]">
        {props.title}
      </span>
    </>
  )
  return (
    <Show when={props.go} fallback={<p>{text}</p>}>
      <button
        type="button"
        class="-m-2 block justify-self-start rounded-md p-2 text-left outline-none hover:underline focus-visible:ring-2 focus-visible:ring-ring"
        onClick={() => props.go?.()}
      >
        {text}
      </button>
    </Show>
  )
}

// A turned page is all tap zones: its left goes back and its right goes
// on, wherever the words sit. A title that opened what it names would
// take the turn back from under a thumb, so only a scrolled one does.
const pressable = (motion: Motion) => motion === "scroll"

/**
 * The page after the last: what you finished and what's next. Drawn into
 * the element the reader's view places at the end of the pages.
 */
export function ChapterEndPage(props: {
  /** What was just read. */
  finished: string
  neighbors: Neighbors
  motion: Motion
  /** Whether the next one is opening. */
  opening: boolean
  go: (neighbor: Neighbor) => void
  /** More about what was finished, such as its readers' comments. */
  children?: JSX.Element
}) {
  const next = () => props.neighbors.next
  return (
    <EdgeFrame
      motion={props.motion}
      hint={
        <Switch>
          <Match when={props.opening}>
            <Spinner class="size-4" />
            Opening…
          </Match>
          <Match when={next()}>
            {props.motion === "scroll" ? "Keep scrolling" : "Turn the page"} to read on
          </Match>
        </Switch>
      }
    >
      <Entry label="Finished" title={props.finished} />
      <div class="grid gap-3">
        <Show
          when={next()}
          fallback={
            <p class="text-[15px] text-muted-foreground">
              {props.neighbors.ending === "caughtUp" ? "You're caught up" : "That's the last one"}
            </p>
          }
        >
          {(neighbor) => (
            <Entry
              label="Next"
              title={neighbor().title}
              go={pressable(props.motion) ? () => props.go(neighbor()) : undefined}
            />
          )}
        </Show>
        {props.children}
      </div>
    </EdgeFrame>
  )
}

/** The page before the first: the chapter you'd go back into. */
export function ChapterStartPage(props: {
  previous: Neighbor
  motion: Motion
  opening: boolean
  go: (neighbor: Neighbor) => void
}) {
  return (
    <EdgeFrame
      motion={props.motion}
      hint={
        <Show
          when={props.opening}
          fallback={
            <>{props.motion === "scroll" ? "Keep scrolling up" : "Turn back again"} to open it</>
          }
        >
          <Spinner class="size-4" />
          Opening…
        </Show>
      }
    >
      <Entry
        label="Previous"
        title={props.previous.title}
        go={pressable(props.motion) ? () => props.go(props.previous) : undefined}
      />
    </EdgeFrame>
  )
}

function EdgeFrame(props: { motion: Motion; hint: JSX.Element; children: JSX.Element }) {
  return (
    <div
      class="flex h-full flex-col items-center justify-center gap-10 bg-background px-8 text-foreground"
      // A scrolled comic's ends are part of its column: tall enough to be
      // a place of their own, short enough to scroll through.
      classList={{ "min-h-[70dvh] py-20": props.motion === "scroll" }}
    >
      <div class="grid w-full max-w-sm gap-8">{props.children}</div>
      <p
        class="flex min-h-5 w-full max-w-sm items-center gap-2 text-[13px] text-muted-foreground"
        aria-live="polite"
      >
        {props.hint}
      </p>
    </div>
  )
}
