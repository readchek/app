import type { JSX } from "solid-js"
import { Wordmark } from "./Wordmark.tsx"

/** A screen of the web app: the wordmark, the screen's title, and its
    content in one narrow column on paper. */
export function Page(props: { title: string; lead?: JSX.Element; children: JSX.Element }) {
  return (
    <div class="mx-auto flex min-h-dvh w-full max-w-lg flex-col px-5 sm:px-6">
      <header class="pt-6 sm:pt-10">
        <a href="https://chek.page" aria-label="Chek" class="inline-block text-link">
          <Wordmark />
        </a>
      </header>
      <main class="flex-1 pt-10 pb-16 sm:pt-14">
        <h1 class="text-[40px] leading-none tracking-[-0.045em] sm:text-5xl">{props.title}</h1>
        {props.lead && (
          <p class="mt-3 text-[17px] leading-snug text-muted-foreground">{props.lead}</p>
        )}
        <div class="mt-8">{props.children}</div>
      </main>
      <footer class="flex flex-wrap justify-between gap-x-6 gap-y-1 pb-8 text-sm text-muted-foreground">
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
