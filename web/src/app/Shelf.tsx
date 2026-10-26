import { For, type JSX, Show } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { cn } from "../lib/cn.ts"
import { Skeleton } from "../components/ui/skeleton.tsx"

/** A titled row of covers that scrolls sideways, as the iOS app's shelves. */
export function Shelf(props: { title: string; detail?: string; children: JSX.Element }) {
  return (
    <section class="mb-10">
      <h2 class="mb-4 flex items-baseline gap-2 text-[22px] leading-tight tracking-[-0.03em]">
        {props.title}
        <Show when={props.detail}>
          <span class="font-sans text-sm font-normal tracking-normal text-muted-foreground">
            {props.detail}
          </span>
        </Show>
      </h2>
      <ul class="-mx-5 flex snap-x scroll-px-5 gap-4 overflow-x-auto px-5 pb-2 [scrollbar-width:none] sm:-mx-8 sm:scroll-px-8 sm:px-8">
        {props.children}
      </ul>
    </section>
  )
}

/** One cover on a shelf with its caption, opening the publication in the reader. `featured` ones are larger, as Continue Reading's. */
export function ShelfItem(props: {
  cover: JSX.Element
  title: string
  detail?: string
  featured?: boolean
  /** The account's key and the publication to open. */
  open: { server: string; publicationId: number }
}) {
  return (
    <li class={cn("shrink-0 snap-start", props.featured ? "w-40 sm:w-48" : "w-32 sm:w-36")}>
      <Link
        to="/read/$server/$publicationId"
        params={{ server: props.open.server, publicationId: String(props.open.publicationId) }}
        class="group block rounded-md focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
      >
        <div class="transition-transform duration-200 group-hover:-translate-y-0.5 group-active:scale-[0.98]">
          {props.cover}
        </div>
        <p class="mt-2 line-clamp-2 text-[15px] leading-snug">{props.title}</p>
        <Show when={props.detail}>
          <p class="mt-0.5 truncate text-[13px] text-muted-foreground">{props.detail}</p>
        </Show>
      </Link>
    </li>
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
