import { For, type JSX, Match, Show, Switch, createSignal, onCleanup, onMount } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { cn } from "../lib/cn.ts"
import { ChevronLeft, ChevronRight } from "../components/icons.tsx"
import { Button } from "../components/ui/button.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"

/**
 * Where a cover leads: a publication in the reader, a series' page, a
 * site's series, or a chapter from a site in the reader. `server` is the
 * account's key.
 */
export type Destination =
  | { server: string; read: number }
  | { server: string; series: number }
  | { server: string; site: string; siteSeries: string }
  | { server: string; site: string; siteSeries: string; chapter: string; title: string }

/** A cover and its caption, leading to `to`. */
function CoverCard(props: { to: Destination; cover: JSX.Element; title: string; detail?: string }) {
  const body = () => (
    <>
      <div class="transition-transform duration-200 group-hover:-translate-y-0.5 group-active:scale-[0.98]">
        {props.cover}
      </div>
      <p class="mt-2 line-clamp-2 text-[15px] leading-snug">{props.title}</p>
      <Show when={props.detail}>
        <p class="mt-0.5 truncate text-[13px] text-muted-foreground">{props.detail}</p>
      </Show>
    </>
  )
  const style =
    "group block rounded-md focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
  return (
    <Switch>
      <Match when={"read" in props.to && props.to}>
        {(to) => (
          <Link
            to="/read/$server/$publicationId"
            params={{ server: to().server, publicationId: String(to().read) }}
            class={style}
          >
            {body()}
          </Link>
        )}
      </Match>
      <Match when={"chapter" in props.to && props.to}>
        {(to) => (
          <Link
            to="/chapter/$server/$extensionId"
            params={{ server: to().server, extensionId: to().site }}
            search={{ series: to().siteSeries, chapter: to().chapter, title: to().title }}
            class={style}
          >
            {body()}
          </Link>
        )}
      </Match>
      <Match when={"siteSeries" in props.to && props.to}>
        {(to) => (
          <Link
            to="/sites/$server/$extensionId/series"
            params={{ server: to().server, extensionId: to().site }}
            search={{ id: to().siteSeries }}
            class={style}
          >
            {body()}
          </Link>
        )}
      </Match>
      <Match when={"series" in props.to && props.to}>
        {(to) => (
          <Link
            to="/shared/$server/series/$seriesId"
            params={{ server: to().server, seriesId: String(to().series) }}
            class={style}
          >
            {body()}
          </Link>
        )}
      </Match>
    </Switch>
  )
}

// Shelves hide their scrollbar and move by swipe. A mouse can't swipe, so
// on a device with one each shelf that overflows gets a pair of arrows.
const mouse = matchMedia("(hover: hover) and (pointer: fine)")

/** A titled row of covers that scrolls sideways, as the iOS app's shelves, with an `action` such as "See all". */
export function Shelf(props: {
  title: string
  detail?: string
  action?: JSX.Element
  children: JSX.Element
}) {
  let row: HTMLUListElement | undefined
  const [reach, setReach] = createSignal({ back: false, forward: false })

  onMount(() => {
    if (!row || !mouse.matches) return
    const list = row
    // Which way the row can still move. `scrollLeft` runs negative in a
    // right-to-left page, so the distance from each end is what counts.
    const measure = () => {
      const left = Math.abs(list.scrollLeft)
      const room = list.scrollWidth - list.clientWidth
      setReach({ back: left > 1, forward: room - left > 1 })
    }
    measure()
    list.addEventListener("scroll", measure, { passive: true })
    const observer = new ResizeObserver(measure)
    observer.observe(list)
    for (const child of list.children) observer.observe(child)
    const children = new MutationObserver(() => {
      for (const child of list.children) observer.observe(child)
      measure()
    })
    children.observe(list, { childList: true })
    onCleanup(() => {
      list.removeEventListener("scroll", measure)
      observer.disconnect()
      children.disconnect()
    })
  })

  // Most of a screenful at a time, so the last cover seen stays in view as a landmark.
  const turn = (direction: 1 | -1) => {
    if (!row) return
    const sign = getComputedStyle(row).direction === "rtl" ? -1 : 1
    row.scrollBy({ left: direction * sign * row.clientWidth * 0.8, behavior: "smooth" })
  }

  const arrow = (direction: 1 | -1) => (
    <Button
      variant="outline"
      size="sm"
      class="size-8 rounded-full px-0 [&_svg]:size-4"
      aria-label={direction > 0 ? "Scroll forward" : "Scroll back"}
      disabled={direction > 0 ? !reach().forward : !reach().back}
      onClick={() => turn(direction)}
    >
      {direction > 0 ? <ChevronRight /> : <ChevronLeft />}
    </Button>
  )

  return (
    <section class="mb-10">
      <div class="mb-4 flex items-baseline justify-between gap-4">
        <h2 class="flex min-w-0 items-baseline gap-2 text-[22px] leading-tight tracking-[-0.03em]">
          {props.title}
          <Show when={props.detail}>
            <span class="font-sans text-sm font-normal tracking-normal text-muted-foreground">
              {props.detail}
            </span>
          </Show>
        </h2>
        <div class="flex items-center gap-3 self-center">
          {props.action}
          <Show when={reach().back || reach().forward}>
            <div class="hidden gap-1.5 md:flex">
              {arrow(-1)}
              {arrow(1)}
            </div>
          </Show>
        </div>
      </div>
      <ul
        ref={(element) => (row = element)}
        class="-mx-5 flex snap-x scroll-px-5 gap-4 overflow-x-auto px-5 pb-2 [scrollbar-width:none] sm:-mx-8 sm:scroll-px-8 sm:px-8"
      >
        {props.children}
      </ul>
    </section>
  )
}

/** One cover on a shelf with its caption. `featured` ones are larger, as Continue Reading's. */
export function ShelfItem(props: {
  to: Destination
  cover: JSX.Element
  title: string
  detail?: string
  featured?: boolean
}) {
  return (
    <li class={cn("shrink-0 snap-start", props.featured ? "w-40 sm:w-48" : "w-32 sm:w-36")}>
      <CoverCard to={props.to} cover={props.cover} title={props.title} detail={props.detail} />
    </li>
  )
}

/** Covers in rows that fill the width, as the iOS app's library grids. */
export function CoverGrid(props: { children: JSX.Element; class?: string }) {
  return (
    <ul
      class={cn(
        "grid grid-cols-[repeat(auto-fill,minmax(7.5rem,1fr))] gap-x-4 gap-y-6 sm:grid-cols-[repeat(auto-fill,minmax(9rem,1fr))]",
        props.class,
      )}
    >
      {props.children}
    </ul>
  )
}

export function GridItem(props: {
  to: Destination
  cover: JSX.Element
  title: string
  detail?: string
}) {
  return (
    <li class="min-w-0">
      <CoverCard to={props.to} cover={props.cover} title={props.title} detail={props.detail} />
    </li>
  )
}

/** A grid the shape of one that's loading. */
export function GridPlaceholder(props: { count?: number }) {
  return (
    <div aria-hidden="true">
      <CoverGrid>
        <For each={Array.from({ length: props.count ?? 12 })}>
          {() => (
            <li>
              <Skeleton class="aspect-[2/3] w-full rounded-md" />
              <Skeleton class="mt-2.5 h-3.5 w-4/5" />
              <Skeleton class="mt-2 h-3 w-1/2" />
            </li>
          )}
        </For>
      </CoverGrid>
    </div>
  )
}

/** A shelf the shape of one that's loading, so nothing jumps when it arrives. */
export function ShelfPlaceholder(props: { featured?: boolean }) {
  return (
    <div class="mb-10" aria-hidden="true">
      <Skeleton class="mb-4 h-6 w-44" />
      <div class="flex gap-4 overflow-hidden">
        <For each={[0, 1, 2, 3, 4, 5, 6]}>
          {() => (
            <div class={cn("shrink-0", props.featured ? "w-40 sm:w-48" : "w-32 sm:w-36")}>
              <Skeleton class="aspect-[2/3] w-full rounded-md" />
              <Skeleton class="mt-2.5 h-3.5 w-4/5" />
              <Skeleton class="mt-2 h-3 w-1/2" />
            </div>
          )}
        </For>
      </div>
    </div>
  )
}
