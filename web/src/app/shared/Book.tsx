import { For, Match, Show, Switch, createMemo } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { Link, useParams } from "@tanstack/solid-router"
import { buttonVariants } from "../../components/ui/button.tsx"
import { accountByKey, accountKey } from "../accounts.ts"
import { Breadcrumbs, type Crumb, Screen } from "../AppShell.tsx"
import { coverPath, progress, publication } from "../client.ts"
import { Cover } from "../Cover.tsx"
import { useTitle } from "../title.ts"
import { progressCaption, publicationTitle, seriesTitle } from "../titles.ts"
import { Failure } from "./Library.tsx"
import { Detail, DetailPlaceholder, bookDetail } from "./Series.tsx"

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

  useTitle(() => (book() ? publicationTitle(book()!.detail) : undefined))

  const trail = (): Crumb[] => {
    const detail = book()?.detail
    const series = detail && seriesTitle(detail)
    return [
      { label: "Shared", to: { to: "/shared" } },
      ...(series && account()
        ? [
            {
              label: series,
              to: {
                to: "/shared/$server/series/$seriesId",
                params: { server: accountKey(account()!), seriesId: String(detail.series.id) },
              },
            } satisfies Crumb,
          ]
        : []),
    ]
  }

  return (
    <Screen title="" back={<Breadcrumbs trail={trail()} />} detail>
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
              <Detail
                cover={
                  <Cover
                    account={account()!}
                    path={detail().hasCover ? coverPath(detail()) : undefined}
                    title={publicationTitle(detail())}
                  />
                }
                heading={
                  <>
                    <h1 class="text-[30px] leading-[1.05] tracking-[-0.04em] [overflow-wrap:anywhere] sm:text-[40px]">
                      {publicationTitle(detail())}
                    </h1>
                    <Show when={authors().length > 0}>
                      <p class="mt-2 text-[17px] lg:text-[15px]">{authors().join(", ")}</p>
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
                  </>
                }
                actions={
                  <Link
                    to="/read/$server/$publicationId"
                    params={{
                      server: accountKey(account()!),
                      publicationId: String(detail().id),
                    }}
                    class={buttonVariants({ class: "w-full sm:w-auto sm:px-8" })}
                  >
                    {status() && status() !== "Finished" ? `Continue · ${status()}` : "Read"}
                  </Link>
                }
              >
                <Show when={detail().description}>
                  {(description) => (
                    <div class="mb-10 grid gap-3 text-[17px] leading-relaxed lg:text-[15px]">
                      <For each={paragraphs(description())}>{(text) => <p>{text}</p>}</For>
                    </div>
                  )}
                </Show>
                <dl class="divide-y border-y text-[15px]">
                  <Row label="Kind" value={bookDetail(detail())} />
                  <For each={credits(detail().contributors)}>
                    {(credit) => <Row label={credit.label} value={credit.names} />}
                  </For>
                  <Row label="Publisher" value={detail().publisher} />
                  <Row label="Published" value={published(detail().published)} />
                  <Row label="Language" value={language(detail().language)} />
                </dl>
              </Detail>
            )
          }}
        </Match>
        <Match when={true}>
          <DetailPlaceholder />
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
export function paragraphs(description: string): string[] {
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

export function language(tag: string | null): string | undefined {
  if (!tag) return undefined
  try {
    return new Intl.DisplayNames(undefined, { type: "language" }).of(tag) ?? tag
  } catch {
    return tag
  }
}
