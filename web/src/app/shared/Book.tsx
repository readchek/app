import { For, Match, Show, Switch, createMemo, createResource } from "solid-js"
import { Link, useNavigate, useParams } from "@tanstack/solid-router"
import { buttonVariants } from "../../components/ui/button.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { accountByKey, accountKey } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
import { coverPath, progress, publication } from "../client.ts"
import { Cover } from "../Cover.tsx"
import { progressCaption, publicationTitle, seriesTitle } from "../titles.ts"
import { Failure } from "./Library.tsx"
import { bookDetail } from "./Series.tsx"

const roles: Record<string, string> = {
  author: "Author",
  illustrator: "Illustrator",
  penciler: "Penciler",
  inker: "Inker",
  colorist: "Colorist",
  letterer: "Letterer",
  coverArtist: "Cover artist",
  editor: "Editor",
  translator: "Translator",
  contributor: "Contributor",
}

/** About a book: its cover, who made it, its description and details, and the button to read it. */
export function Book() {
  const navigate = useNavigate()
  const params = useParams({ from: "/app/shared/$server/books/$publicationId" })
  const account = createMemo(() => {
    const found = accountByKey(params().server)
    return found && !found.expired ? found : undefined
  })
  const [book] = createResource(
    () => account() && { account: account()!, id: Number(params().publicationId) },
    async ({ account, id }) => {
      const [detail, saved] = await Promise.all([publication(account, id), progress(account, id)])
      return { detail, saved }
    },
  )

  return (
    <Screen
      title=""
      back={<BackButton label="Back" fallback={() => void navigate({ to: "/shared" })} />}
      narrow
    >
      <Switch>
        <Match when={!account()}>
          <Failure
            error={new Error("You're not signed in to this book's server. Add it in Settings.")}
          />
        </Match>
        <Match when={book.error}>
          <Failure error={book.error} />
        </Match>
        <Match when={book()}>
          {(loaded) => {
            const detail = () => loaded().detail
            const authors = () =>
              detail()
                .contributors.filter((c) => c.role === "author")
                .map((c) => c.name)
            const status = () => progressCaption(loaded().saved)
            return (
              <>
                <div class="flex flex-col gap-6 sm:flex-row sm:items-end sm:gap-8">
                  <div class="w-40 shrink-0 sm:w-48">
                    <Cover
                      account={account()!}
                      path={detail().hasCover ? coverPath(detail()) : undefined}
                      title={publicationTitle(detail())}
                    />
                  </div>
                  <div class="min-w-0">
                    <h1 class="text-[30px] leading-[1.05] tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
                      {publicationTitle(detail())}
                    </h1>
                    <Show when={authors().length > 0}>
                      <p class="mt-2 text-[17px]">{authors().join(", ")}</p>
                    </Show>
                    <Show when={seriesTitle(detail())}>
                      <Link
                        to="/shared/$server/series/$seriesId"
                        params={{
                          server: accountKey(account()!),
                          seriesId: String(detail().series.id),
                        }}
                        class="mt-1 inline-block text-[15px] text-link hover:underline"
                      >
                        {seriesTitle(detail())}
                      </Link>
                    </Show>
                    <Link
                      to="/read/$server/$publicationId"
                      params={{
                        server: accountKey(account()!),
                        publicationId: String(detail().id),
                      }}
                      class={buttonVariants({ class: "mt-5 w-full sm:w-auto sm:px-8" })}
                    >
                      {status() && status() !== "Finished" ? `Continue · ${status()}` : "Read"}
                    </Link>
                  </div>
                </div>
                <Show when={detail().description}>
                  {(description) => (
                    <div class="mt-10 grid gap-3 text-[17px] leading-relaxed">
                      <For each={paragraphs(description())}>{(text) => <p>{text}</p>}</For>
                    </div>
                  )}
                </Show>
                <dl class="mt-10 divide-y border-y text-[15px]">
                  <Row label="Kind" value={bookDetail(detail())} />
                  <For each={credits(detail().contributors)}>
                    {(credit) => <Row label={credit.label} value={credit.names} />}
                  </For>
                  <Row label="Publisher" value={detail().publisher} />
                  <Row label="Published" value={published(detail().published)} />
                  <Row label="Language" value={language(detail().language)} />
                </dl>
              </>
            )
          }}
        </Match>
        <Match when={true}>
          <div class="flex flex-col gap-6 sm:flex-row sm:items-end" aria-hidden="true">
            <Skeleton class="aspect-[2/3] w-40 rounded-md sm:w-48" />
            <div class="grid gap-3">
              <Skeleton class="h-8 w-56" />
              <Skeleton class="h-4 w-32" />
              <Skeleton class="mt-3 h-11 w-32 rounded-full" />
            </div>
          </div>
        </Match>
      </Switch>
    </Screen>
  )
}

/** Everyone credited other than the authors, one row per role, in the order the file first names each. */
function credits(contributors: { name: string; role: string | null }[]) {
  const byRole = new Map<string, string[]>()
  for (const person of contributors) {
    if (person.role === "author") continue
    const role = person.role ?? "contributor"
    byRole.set(role, [...(byRole.get(role) ?? []), person.name])
  }
  return [...byRole].map(([role, names]) => ({
    label: (roles[role] ?? "Contributor") + (names.length > 1 ? "s" : ""),
    names: names.join(", "),
  }))
}

function Row(props: { label: string; value: string | null | undefined }) {
  return (
    <Show when={props.value}>
      <div class="flex justify-between gap-6 py-3">
        <dt class="text-muted-foreground">{props.label}</dt>
        <dd class="min-w-0 text-end">{props.value}</dd>
      </div>
    </Show>
  )
}

// Descriptions can be HTML, as EPUB ones often are. Only their text is
// shown, a paragraph per block, so nothing from the file runs or loads.
function paragraphs(description: string): string[] {
  const document = new DOMParser().parseFromString(description, "text/html")
  for (const element of document.querySelectorAll("br")) element.replaceWith("\n")
  for (const element of document.querySelectorAll("p, div, li, h1, h2, h3, h4")) {
    element.append("\n\n")
  }
  return (document.body.textContent ?? "")
    .split(/\n\s*\n/)
    .map((text) => text.replace(/\s+/g, " ").trim())
    .filter(Boolean)
}

function published(value: string | null): string | undefined {
  if (!value) return undefined
  const [year, month, day] = value.split("-").map(Number)
  if (!year) return value
  const date = new Date(Date.UTC(year, (month ?? 1) - 1, day ?? 1))
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: month ? "long" : undefined,
    day: day ? "numeric" : undefined,
    timeZone: "UTC",
  }).format(date)
}

function language(tag: string | null): string | undefined {
  if (!tag) return undefined
  try {
    return new Intl.DisplayNames(undefined, { type: "language" }).of(tag) ?? tag
  } catch {
    return tag
  }
}
