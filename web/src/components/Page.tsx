import type { JSX } from "solid-js"
import { Wordmark } from "./Wordmark.tsx"

/** A screen of the web app: the blue band with the wordmark and the
    screen's title, then its content on paper, overlapping the band. */
export function Page(props: {
  title: string
  lead?: JSX.Element
  /** A short aside in a butter speech bubble, like the store art's. */
  bubble?: string
  children: JSX.Element
}) {
  return (
    <div class="flex min-h-dvh flex-col">
      <header class="relative overflow-hidden bg-hero text-hero-foreground">
        {/* Soft light across the blue, as on the store art. */}
        <div
          aria-hidden="true"
          class="pointer-events-none absolute -top-40 left-1/2 h-80 w-[44rem] -translate-x-1/2 rounded-full bg-white/10 blur-3xl"
        />
        <div class="relative mx-auto max-w-xl px-4 pt-6 pb-24 sm:px-6 sm:pt-8 sm:pb-28">
          <div class="flex items-center justify-between gap-4">
            <Wordmark />
            {props.bubble && (
              <span
                aria-hidden="true"
                class="relative rotate-[-5deg] rounded-[50%] bg-butter px-4 py-2.5 font-display text-[15px] leading-[1.05] tracking-[-0.03em] text-butter-foreground shadow-lg shadow-black/15 sm:px-5 sm:py-3 sm:text-lg"
              >
                {props.bubble}
                <span class="absolute -bottom-1 left-5 size-4 rotate-45 rounded-[3px] bg-butter" />
              </span>
            )}
          </div>
          <h1 class="mt-10 text-[44px] leading-[0.95] tracking-[-0.045em] sm:mt-14 sm:text-6xl">
            {props.title}
          </h1>
          {props.lead && (
            <p class="mt-3 max-w-md text-[17px] leading-snug text-hero-foreground/80 sm:text-lg">
              {props.lead}
            </p>
          )}
        </div>
      </header>
      <main class="relative mx-auto -mt-16 w-full max-w-xl flex-1 px-4 pb-12 sm:-mt-20 sm:px-6">
        {props.children}
      </main>
      <footer class="mx-auto flex w-full max-w-xl flex-wrap items-center justify-between gap-x-6 gap-y-1 px-4 pb-8 text-sm text-muted-foreground sm:px-6">
        <span>For the love of the next chapter.</span>
        <span>
          <a class="hover:text-foreground" href="https://chek.page/privacy">
            Privacy
          </a>
          {" · "}
          <a class="hover:text-foreground" href="https://chek.page/support">
            Support
          </a>
        </span>
      </footer>
    </div>
  )
}
