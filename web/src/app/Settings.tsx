import { For, Show } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { Plus } from "../components/icons.tsx"
import { Badge } from "../components/ui/badge.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import { accounts, host, removeAccount } from "./accounts.ts"
import { Screen } from "./AppShell.tsx"
import { clearImages } from "./images.ts"

/** The servers you're signed in to, and signing in to more. */
export function Settings() {
  const signOut = async (server: string) => {
    await removeAccount(server)
    // Nothing of a server's is kept once no one is signed in to any.
    if (accounts().length === 0) await clearImages()
  }

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
                <div class="min-w-0">
                  <p class="flex flex-wrap items-center gap-2 font-semibold">
                    <span class="truncate">{host(account.server)}</span>
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
                </div>
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
    </Screen>
  )
}
