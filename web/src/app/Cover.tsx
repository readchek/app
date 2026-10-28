import { Show, createSignal, onCleanup, onMount } from "solid-js"
import { cn } from "../lib/cn.ts"
import type { Account } from "./accounts.ts"
import { loadImage } from "./images.ts"

/** A cover filling a 2:3 frame, so shelves and grids line up, with a quiet
    stand-in while it loads or when there isn't one. It loads only once
    it's near the screen. After the iOS app's CoverView. */
export function Cover(props: { account: Account; path?: string; title: string; class?: string }) {
  let frame: HTMLDivElement | undefined
  const [src, setSrc] = createSignal<string>()
  const [phase, setPhase] = createSignal<"waiting" | "loaded" | "missing">(
    props.path ? "waiting" : "missing",
  )

  onMount(() => {
    const path = props.path
    if (!path || !frame) return
    let url: string | undefined
    let live = true
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return
        observer.disconnect()
        loadImage(props.account, path).then(
          (blob) => {
            if (!live) return
            url = URL.createObjectURL(blob)
            setSrc(url)
          },
          () => live && setPhase("missing"),
        )
      },
      { rootMargin: "300px" },
    )
    observer.observe(frame)
    onCleanup(() => {
      live = false
      observer.disconnect()
      if (url) URL.revokeObjectURL(url)
    })
  })

  return (
    <div
      ref={(element) => (frame = element)}
      class={cn(
        "relative aspect-[2/3] w-full overflow-hidden rounded-md bg-muted",
        // A hairline keeps white covers from melting into the page. It's a
        // border, not a shadow: Safari repaints shadows as a page scrolls,
        // and a shelf of them makes scrolling stutter.
        "after:pointer-events-none after:absolute after:inset-0 after:rounded-md after:border after:border-foreground/10",
        props.class,
      )}
      aria-hidden="true"
    >
      <Show when={phase() === "missing"}>
        <p class="absolute inset-0 flex items-center justify-center p-2.5 text-center text-[13px] leading-snug text-muted-foreground [overflow-wrap:anywhere]">
          <span class="line-clamp-4">{props.title}</span>
        </p>
      </Show>
      <Show when={src()}>
        <img
          src={src()}
          alt=""
          decoding="async"
          class={cn(
            "size-full object-cover transition-opacity duration-200",
            phase() === "loaded" ? "opacity-100" : "opacity-0",
          )}
          onLoad={() => setPhase("loaded")}
          onError={() => setPhase("missing")}
        />
      </Show>
    </div>
  )
}
