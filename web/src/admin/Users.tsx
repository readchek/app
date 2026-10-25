import { For, Match, Switch, createResource } from "solid-js"
import { Link } from "@tanstack/solid-router"
import { AlertCircle, ChevronRight } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Badge } from "../components/ui/badge.tsx"
import { buttonVariants } from "../components/ui/button.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"
import type { User } from "../api.ts"
import { Heading, adminSession } from "./AdminShell.tsx"
import { libraries, users } from "./api.ts"
import { call, count, message } from "./util.ts"

export function Users() {
  const session = adminSession()
  const [people] = createResource(() => call(users(session)))
  const [all] = createResource(() => call(libraries(session)))

  // Grants can name libraries that were deleted since, so only live ones count.
  const access = (user: User) => {
    if (user.role === "admin") return "Every library"
    const granted = all()?.filter((l) => user.libraryIds.includes(l.id)) ?? []
    if (granted.length === 0) return "No libraries yet"
    if (granted.length <= 2) return granted.map((l) => l.name).join(" and ")
    return count(granted.length, "library", "libraries")
  }

  return (
    <>
      <Heading title="People" lead="Who can sign in, and which libraries each reader sees.">
        <Link to="/admin/users/new" class={buttonVariants({ size: "sm" })}>
          Add person
        </Link>
      </Heading>
      <Switch>
        <Match when={people.error}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{message(people.error)}</p>
          </Alert>
        </Match>
        <Match when={people()}>
          {(items) => (
            <ul class="divide-y border-y">
              <For each={items()}>
                {(user) => (
                  <li>
                    <Link
                      to="/admin/users/$userId"
                      params={{ userId: String(user.id) }}
                      class="-mx-3 flex items-center gap-4 rounded-xl px-3 py-4 transition-colors hover:bg-muted/60 focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
                    >
                      <span class="grid min-w-0 flex-1 gap-0.5">
                        <span class="flex items-center gap-2 font-semibold">
                          <span class="truncate">{user.name}</span>
                          {user.id === session.user.id && <Badge variant="outline">You</Badge>}
                        </span>
                        <span class="truncate text-[15px] text-muted-foreground">
                          {access(user)}
                        </span>
                      </span>
                      <Badge variant={user.role === "admin" ? "default" : "secondary"}>
                        {user.role === "admin" ? "Admin" : "Reader"}
                      </Badge>
                      <ChevronRight />
                    </Link>
                  </li>
                )}
              </For>
            </ul>
          )}
        </Match>
        <Match when={true}>
          <div aria-busy="true" class="divide-y border-y">
            <p class="sr-only" role="status">
              Loading…
            </p>
            <For each={[0, 1, 2]}>
              {() => (
                <div class="grid gap-2 py-4">
                  <Skeleton class="h-4 w-28" />
                  <Skeleton class="h-4 w-44" />
                </div>
              )}
            </For>
          </div>
        </Match>
      </Switch>
    </>
  )
}
