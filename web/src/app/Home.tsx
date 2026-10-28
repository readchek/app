import { For, Match, Show, Switch, createMemo, untrack } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { Link } from "@tanstack/solid-router"
import { AlertCircle } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { buttonVariants } from "../components/ui/button.tsx"
import { type Account, accountKey, accounts, host } from "./accounts.ts"
import {
  type Continued,
  type Page,
  type PublicationSummary,
  continueReading,
  coverPath,
  recentlyAdded,
} from "./client.ts"
import { Cover } from "./Cover.tsx"
import { Screen } from "./AppShell.tsx"
import { type Destination, Shelf, ShelfItem, ShelfPlaceholder } from "./Shelf.tsx"
import { remember, remembered } from "./snapshot.ts"
import {
  type InstalledExtension,
  type RemoteSeriesItem,
  installedExtensions,
  searchSite,
} from "./sites/api.ts"
import { continuingSiteSeries } from "./sites/positions.ts"
import { progressCaption, publicationTitle, seriesTitle } from "./titles.ts"

const shelfSize = 20

/** What Reading Now keeps of `account`'s answer to `what`, for showing at once next time. */
function kept(account: Account, what: string): string {
  return `${accountKey(account)}|${what}`
}

/** Reading Now: what you're reading on every server first, then what's new on each, then what each site shows. */
export function Home() {
  const signedIn = () => accounts().filter((a) => !a.expired)
  const expired = () => accounts().filter((a) => a.expired)

  return (
    <Screen title="Reading Now">
      <For each={expired()}>
        {(account) => (
          <Alert variant="destructive" class="mb-8">
            <AlertCircle />
            <p>
              You were signed out of {host(account.server)}.{" "}
              <Link
                to="/sign-in"
                search={{ server: account.server }}
                class={buttonVariants({ variant: "link", size: "inline" })}
              >
                Sign in again
              </Link>
            </p>
          </Alert>
        )}
      </For>
      <ContinueReading accounts={signedIn()} />
      <For each={signedIn()}>
        {(account) => <RecentlyAdded account={account} showHost={accounts().length > 1} />}
      </For>
      <For each={signedIn()}>{(account) => <SiteShelves account={account} />}</For>
    </Screen>
  )
}

type Reading = Continued & { account: Account }

/** One cover on Continue Reading, from a server's library or a site. */
type Entry = {
  key: string
  account: Account
  to: Destination
  cover: string | undefined
  title: string
  detail: string
  at: string
}

function ContinueReading(props: { accounts: Account[] }) {
  // One shelf for every server, most recently read first. A server that
  // can't be reached shows what it had last time.
  const read = (account: Account) =>
    (remembered<Continued[]>(kept(account, "reading")) ?? []).map((item): Reading => ({
      ...item,
      account,
    }))
  const before = untrack(() => props.accounts.flatMap(read))
  const [reading] = createResource(
    () => props.accounts,
    async (list) => {
      const pages = await Promise.all(
        list.map(async (account) => {
          try {
            const { items } = await continueReading(account, { limit: shelfSize })
            remember(kept(account, "reading"), items)
            return items.map((item): Reading => ({ ...item, account }))
          } catch {
            return read(account)
          }
        }),
      )
      return pages.flat()
    },
  )

  // Chapters read straight from a site join them; this browser keeps
  // their places.
  const entries = createMemo((): Entry[] => {
    const fromServers = (reading.latest ?? before).map((item) => ({
      key: `${accountKey(item.account)}/${item.publication.id}`,
      account: item.account,
      to: { server: accountKey(item.account), read: item.publication.id },
      cover: item.publication.hasCover ? coverPath(item.publication) : undefined,
      title: publicationTitle(item.publication),
      detail: [seriesTitle(item.publication), progressCaption(item.progress)]
        .filter(Boolean)
        .join(" · "),
      at: item.progress.updatedAt ?? "",
    }))
    const fromSites = continuingSiteSeries().flatMap((place) => {
      const account = props.accounts.find((a) => accountKey(a) === place.server)
      if (!account) return []
      return [
        {
          key: `${place.server}/${place.extensionId}/${place.chapterId}`,
          account,
          to: {
            server: place.server,
            site: place.extensionId,
            siteSeries: place.seriesId,
            chapter: place.chapterId,
            title: place.chapterTitle,
          },
          cover: place.coverUrl ?? undefined,
          title: place.seriesTitle,
          // How far comes first, since chapter titles run long.
          detail: [
            place.progression >= 1
              ? "Finished"
              : `${Math.max(1, Math.round(place.progression * 100))}%`,
            place.chapterTitle,
          ].join(" · "),
          at: place.openedAt,
        },
      ]
    })
    return [...fromServers, ...fromSites]
      .sort((a, b) => b.at.localeCompare(a.at))
      .slice(0, shelfSize)
  })

  return (
    <Switch>
      <Match when={reading.loading && !reading.latest && before.length === 0}>
        <ShelfPlaceholder featured />
      </Match>
      <Match when={entries().length}>
        <Shelf title="Continue Reading">
          <For each={entries()}>
            {(item) => (
              <ShelfItem
                featured
                to={item.to}
                cover={<Cover account={item.account} path={item.cover} title={item.title} />}
                title={item.title}
                detail={item.detail}
              />
            )}
          </For>
        </Shelf>
      </Match>
    </Switch>
  )
}

function RecentlyAdded(props: { account: Account; showHost: boolean }) {
  const before = untrack(() =>
    remembered<Page<PublicationSummary>>(kept(props.account, "recently-added")),
  )
  const [added] = createResource(
    () => props.account,
    async (account) => {
      const page = await recentlyAdded(account, { limit: shelfSize })
      remember(kept(account, "recently-added"), page)
      return page
    },
  )
  const detail = () => (props.showHost ? host(props.account.server) : undefined)

  return (
    <Switch>
      <Match when={added.error && !before}>
        <section class="mb-10">
          <h2 class="mb-3 text-[22px] leading-tight tracking-[-0.03em]">Recently Added</h2>
          <Alert variant="destructive">
            <AlertCircle />
            <p>
              {added.error instanceof Error
                ? added.error.message
                : "Couldn't load this server's books."}
            </p>
          </Alert>
        </section>
      </Match>
      <Match when={(added.error ? undefined : added.latest) ?? before}>
        {(page) => (
          <Show
            when={page().items.length > 0}
            fallback={
              <section class="mb-10">
                <h2 class="mb-2 text-[22px] leading-tight tracking-[-0.03em]">Recently Added</h2>
                <p class="text-[15px] text-muted-foreground">
                  Nothing on {host(props.account.server)} yet. Books and comics show up here once
                  its admin adds a library.
                </p>
              </section>
            }
          >
            <Shelf title="Recently Added" detail={detail()}>
              <For each={page().items}>
                {(publication) => (
                  <ShelfItem
                    to={{ server: accountKey(props.account), read: publication.id }}
                    cover={
                      <Cover
                        account={props.account}
                        path={publication.hasCover ? coverPath(publication) : undefined}
                        title={publicationTitle(publication)}
                      />
                    }
                    title={publicationTitle(publication)}
                    detail={seriesTitle(publication)}
                  />
                )}
              </For>
            </Shelf>
          </Show>
        )}
      </Match>
      <Match when={true}>
        <ShelfPlaceholder />
      </Match>
    </Switch>
  )
}

/** A site's series as Reading Now keeps them. */
type SiteShelfItems = { site: InstalledExtension; items: RemoteSeriesItem[] }

/**
 * A shelf for each site the account has added, with the series it shows
 * first, as the iOS app's home. A site that's slow or down today keeps
 * the shelf it had last time, and one that never answered stays out.
 */
function SiteShelves(props: { account: Account }) {
  // Undefined until the account's sites have answered once, so an account
  // without sites shows a placeholder only on its first visit.
  const before = untrack(() => remembered<SiteShelfItems[]>(kept(props.account, "sites")))
  const [shelves] = createResource(
    () => props.account,
    async (account) => {
      const sites = (await installedExtensions(account)).filter((site) => site.usable)
      const shelves = await Promise.all(
        sites.map(async (site): Promise<SiteShelfItems | undefined> => {
          try {
            const page = await searchSite(account, site.id, { page: 1 })
            return { site, items: page.items.slice(0, shelfSize) }
          } catch {
            const last = before?.find((shelf) => shelf.site.id === site.id)
            return last && { site, items: last.items }
          }
        }),
      )
      const answered = shelves.filter(
        (shelf): shelf is SiteShelfItems => shelf !== undefined && shelf.items.length > 0,
      )
      remember(kept(account, "sites"), answered)
      return answered
    },
  )

  return (
    <Show
      when={shelves.latest ?? before}
      fallback={
        <Show when={shelves.loading}>
          <ShelfPlaceholder />
        </Show>
      }
    >
      {(list) => (
        <For each={list()}>
          {(shelf) => (
            <Shelf
              title={shelf.site.name}
              action={
                <Link
                  to="/sites/$server/$extensionId"
                  params={{ server: accountKey(props.account), extensionId: shelf.site.id }}
                  class={buttonVariants({ variant: "link", size: "inline" })}
                >
                  See all
                </Link>
              }
            >
              <For each={shelf.items}>
                {(item) => (
                  <ShelfItem
                    to={{
                      server: accountKey(props.account),
                      site: shelf.site.id,
                      siteSeries: item.id,
                    }}
                    cover={
                      <Cover
                        account={props.account}
                        path={item.coverUrl ?? undefined}
                        title={item.title}
                      />
                    }
                    title={item.title}
                  />
                )}
              </For>
            </Shelf>
          )}
        </For>
      )}
    </Show>
  )
}
