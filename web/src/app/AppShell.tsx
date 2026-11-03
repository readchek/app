import { For, type JSX, Show } from "solid-js"
import { Link, type NavigateOptions, Outlet, useRouter } from "@tanstack/solid-router"
import { Wordmark } from "../components/Wordmark.tsx"
import { BookOpen, Building, ChevronLeft, ChevronRight, Gear, Globe } from "../components/icons.tsx"
import { Button } from "../components/ui/button.tsx"
import { cn } from "../lib/cn.ts"
import { accounts } from "./accounts.ts"
import { SearchButton, SearchPalette } from "./SearchPalette.tsx"
import { Welcome } from "./SignIn.tsx"
import { useTitle } from "./title.ts"

// The app's places, as the iOS app's tabs. On a wide window they're a
// sidebar, as on iPad; in a narrower window, such as half a laptop's
// screen, the sidebar keeps only its icons, as a website's rail does; on a
// phone they're a bar along the bottom. Search isn't one: it opens over
// every screen, from the top of either.
const places = [
  { to: "/", label: "Reading Now", icon: BookOpen },
  { to: "/shared", label: "Shared", icon: Building },
  { to: "/sites", label: "Sites", icon: Globe },
  { to: "/settings", label: "Settings", icon: Gear },
] as const

/** The frame of every reading screen, or the welcome when no server is signed in yet. */
export function AppShell() {
  return (
    <Show when={accounts().length > 0} fallback={<Welcome />}>
      <div class="min-h-dvh md:grid md:grid-cols-[4.5rem_1fr] lg:grid-cols-[15rem_1fr]">
        <aside class="sticky top-0 hidden h-dvh flex-col border-e bg-card/40 px-3 pt-8 pb-6 md:flex lg:px-4">
          <Link
            to="/"
            aria-label="Chek, Reading Now"
            class="inline-block self-center text-link lg:ms-2 lg:self-start"
          >
            <Wordmark class="[&>span]:hidden lg:[&>span]:inline" />
          </Link>
          <SearchButton class="mt-7" compact />
          <nav aria-label="Chek" class="mt-4 grid gap-0.5">
            <For each={places}>
              {(place) => (
                <Link
                  to={place.to}
                  activeOptions={{ exact: place.to === "/" }}
                  class="flex h-10 items-center justify-center gap-3 rounded-lg px-3 text-[15px] font-semibold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground data-[status=active]:bg-muted data-[status=active]:text-foreground lg:justify-start [&_svg]:size-5 [&_svg]:text-link"
                  activeProps={{ "aria-current": "page" }}
                  title={place.label}
                >
                  <place.icon />
                  <span class="hidden lg:inline">{place.label}</span>
                </Link>
              )}
            </For>
          </nav>
          <p class="mt-auto hidden px-3 text-sm text-muted-foreground lg:block">
            For the love of the next chapter.
          </p>
        </aside>
        <div class="min-w-0 pb-[calc(4.5rem+env(safe-area-inset-bottom))] md:pb-0">
          {/* The bars are nearly opaque rather than blurred, since Safari
              redraws a blur behind them on every frame of a scroll. */}
          <div class="sticky top-0 z-40 border-b bg-background/95 px-5 pt-[calc(0.5rem+env(safe-area-inset-top))] pb-2 sm:px-8 md:hidden">
            <SearchButton class="mx-auto max-w-7xl" />
          </div>
          <Outlet />
        </div>
        <SearchPalette />
        <nav
          aria-label="Chek"
          class="fixed inset-x-0 bottom-0 z-40 flex justify-around border-t bg-background/95 px-2 pt-1.5 pb-[calc(0.375rem+env(safe-area-inset-bottom))] md:hidden"
        >
          <For each={places}>
            {(place) => (
              <Link
                to={place.to}
                activeOptions={{ exact: place.to === "/" }}
                class="flex min-w-14 flex-col items-center gap-0.5 rounded-lg px-2 py-1 text-[11px] font-semibold text-muted-foreground data-[status=active]:text-link [&_svg]:size-6"
                activeProps={{ "aria-current": "page" }}
              >
                <place.icon />
                {place.label}
              </Link>
            )}
          </For>
        </nav>
      </div>
    </Show>
  )
}

/**
 * A row of a list that leads somewhere. The whole row answers the mouse,
 * as a website's does, lighting up a little wider than the list's lines.
 */
export const row =
  "flex items-center gap-3.5 rounded-lg transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none lg:-mx-3 lg:px-3"

/** A screen above this one, for the way back to it. */
export type Crumb = { label: string; to: NavigateOptions }

/**
 * The way back from a pushed screen. On a wide window it's the trail of
 * screens above this one, as a website's breadcrumbs, since the browser
 * already has a Back button. On a phone it's one Back button to the
 * nearest, as the iOS app's, which goes back where the person came from
 * or to that screen when they opened this one directly.
 */
export function Breadcrumbs(props: { trail: Crumb[] }) {
  const router = useRouter()
  const nearest = () => props.trail[props.trail.length - 1]
  return (
    <Show when={nearest()}>
      {(back) => (
        <>
          <Button
            variant="ghost"
            size="sm"
            class="-ms-3 mb-4 text-link lg:hidden [&_svg]:size-5"
            onClick={() =>
              router.history.canGoBack()
                ? router.history.back()
                : void router.navigate({ ...back().to })
            }
          >
            <ChevronLeft />
            {back().label}
          </Button>
          <nav aria-label="Breadcrumb" class="mb-5 hidden lg:block">
            <ol class="flex flex-wrap items-center gap-1 text-sm text-muted-foreground [&_svg]:size-4 [&_svg]:opacity-60">
              <For each={props.trail}>
                {(crumb, index) => (
                  <li class="flex items-center gap-1">
                    <Show when={index() > 0}>
                      <ChevronRight />
                    </Show>
                    <Link
                      {...crumb.to}
                      class="rounded-sm transition-colors hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
                    >
                      {crumb.label}
                    </Link>
                  </li>
                )}
              </For>
            </ol>
          </nav>
        </>
      )}
    </Show>
  )
}

/**
 * A reading screen's large title, as the iOS app's, and its content. Screens
 * that draw their own title pass an empty one and set the tab's themselves.
 * `narrow` screens are one column of text, such as Settings; `detail`
 * screens are one thing, such as a series, and open out into two columns on
 * a wide window.
 */
export function Screen(props: {
  title: string
  back?: JSX.Element
  lead?: JSX.Element
  actions?: JSX.Element
  narrow?: boolean
  detail?: boolean
  children: JSX.Element
}) {
  useTitle(() => props.title)
  return (
    <main
      class={cn(
        "mx-auto w-full px-5 pt-8 pb-16 sm:px-8 lg:pt-10",
        props.narrow ? "max-w-2xl" : props.detail ? "max-w-2xl lg:max-w-5xl" : "max-w-7xl",
      )}
    >
      {props.back}
      <Show when={props.title}>
        <header class="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div class="min-w-0">
            <h1 class="text-[34px] leading-none tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
              {props.title}
            </h1>
            <Show when={props.lead}>
              <p class="mt-2.5 text-[17px] leading-snug text-muted-foreground">{props.lead}</p>
            </Show>
          </div>
          {props.actions}
        </header>
      </Show>
      {props.children}
    </main>
  )
}
