import { type JSX, For, Show } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { ChevronRight, Plus } from "../../components/icons.tsx"
import { Badge } from "../../components/ui/badge.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import { Choice } from "../../components/Choice.tsx"
import { accountKey, accounts, host, removeAccount } from "../accounts.ts"
import { Screen } from "../AppShell.tsx"
import { clearFiles } from "../files.ts"
import { clearImages } from "../images.ts"
import {
  bookSettings,
  changeBookSettings,
  changeComicSettings,
  comicSettings,
} from "../reader/settings.ts"

/** Signs out of a server, and forgets what's kept from servers once none is left. */
export async function signOutOf(server: string) {
  await removeAccount(server)
  if (accounts().length === 0) await Promise.all([clearImages(), clearFiles()])
}

/** The servers you're signed in to, how books and comics read, and about Chek. */
export function Settings() {
  const signOut = signOutOf

  return (
    <Screen title="Settings" narrow>
      <section>
        <h2 class="mb-1 text-sm font-semibold">Servers</h2>
        <p class="mb-3 text-[15px] text-muted-foreground">
          Reading Now shows what's on every server you sign in to.
        </p>
        <ul class="divide-y border-y">
          <For each={accounts()}>
            {(account) => (
              <li class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 py-4">
                <Link
                  to="/settings/$server"
                  params={{ server: accountKey(account) }}
                  class="group min-w-0 rounded-lg focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
                >
                  <p class="flex flex-wrap items-center gap-2 font-semibold">
                    <span class="truncate group-hover:underline">{host(account.server)}</span>
                    <Show when={account.user.demo}>
                      <Badge variant="butter">Demo</Badge>
                    </Show>
                    <Show when={account.expired}>
                      <Badge variant="destructive">Signed out</Badge>
                    </Show>
                  </p>
                  <p class="mt-0.5 text-[15px] text-muted-foreground">
                    {account.user.name}
                    {account.user.role === "admin" ? ", admin" : ""}
                  </p>
                </Link>
                <div class="flex items-center gap-1">
                  <Show
                    when={account.expired}
                    fallback={
                      <Show when={account.user.role === "admin"}>
                        <Link
                          to="/admin"
                          search={{ server: account.server }}
                          class={buttonVariants({ variant: "ghost", size: "sm" })}
                        >
                          Admin panel
                        </Link>
                      </Show>
                    }
                  >
                    <Link
                      to="/sign-in"
                      search={{ server: account.server }}
                      class={buttonVariants({ variant: "ghost", size: "sm" })}
                    >
                      Sign in again
                    </Link>
                  </Show>
                  <Button
                    variant="ghost"
                    size="sm"
                    class="text-destructive"
                    onClick={() => void signOut(account.server)}
                  >
                    Sign out
                  </Button>
                </div>
              </li>
            )}
          </For>
        </ul>
        <Link to="/sign-in" class={buttonVariants({ variant: "outline", class: "mt-6" })}>
          <Plus />
          Add a server
        </Link>
      </section>

      <Section
        title="Reading"
        detail="How books and comics open. You can change these as you read."
      >
        <div class="grid gap-5">
          <Choice
            label="Book theme"
            value={bookSettings().theme}
            options={[
              { value: "automatic", label: "Auto" },
              { value: "light", label: "Light" },
              { value: "sepia", label: "Sepia" },
              { value: "dark", label: "Dark" },
            ]}
            onChange={(theme) => changeBookSettings({ theme })}
          />
          <Choice
            label="Book font"
            value={bookSettings().font}
            options={[
              { value: "default", label: "Book's" },
              { value: "serif", label: "Serif" },
              { value: "sans", label: "Sans serif" },
            ]}
            onChange={(font) => changeBookSettings({ font })}
          />
          <Choice
            label="Comic pages"
            value={comicSettings().flow}
            options={[
              { value: "automatic", label: "Automatic" },
              { value: "paged", label: "Turn" },
              { value: "scrolled", label: "Scroll" },
            ]}
            onChange={(flow) => changeComicSettings({ flow })}
          />
          <Choice
            label="Two comic pages at once"
            value={comicSettings().spreads}
            options={[
              { value: "automatic", label: "When wide" },
              { value: "single", label: "Never" },
              { value: "double", label: "Always" },
            ]}
            onChange={(spreads) => changeComicSettings({ spreads })}
          />
        </div>
      </Section>

      <Section title="About">
        <ul class="divide-y border-y">
          <AboutLink href="https://chek.page">chek.page</AboutLink>
          <AboutLink href="https://chek.page/support">Report a problem</AboutLink>
          <AboutLink href="https://chek.page/privacy">Privacy policy</AboutLink>
        </ul>
      </Section>
    </Screen>
  )
}

function Section(props: { title: string; detail?: string; children: JSX.Element }) {
  return (
    <section class="mt-12">
      <h2 class="mb-1 text-sm font-semibold">{props.title}</h2>
      <Show when={props.detail}>
        <p class="mb-4 text-[15px] text-muted-foreground">{props.detail}</p>
      </Show>
      {props.children}
    </section>
  )
}

function AboutLink(props: { href: string; children: JSX.Element }) {
  return (
    <li>
      <a
        href={props.href}
        target="_blank"
        rel="noopener"
        class="flex items-center justify-between py-3.5 text-[15px] font-semibold text-link hover:underline focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
      >
        {props.children}
        <span class="text-muted-foreground [&_svg]:size-4">
          <ChevronRight />
        </span>
      </a>
    </li>
  )
}
