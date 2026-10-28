import { For, type JSX, Match, Show, Switch, createSignal } from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { useNavigate, useParams } from "@tanstack/solid-router"
import { AlertCircle, CheckCircle, Spinner } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { Badge } from "../../components/ui/badge.tsx"
import { Button } from "../../components/ui/button.tsx"
import { Input, Label } from "../../components/ui/input.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { ContentRatingsForm } from "../../routes/ContentSettings.tsx"
import { type Account, accountByKey, expire, host } from "../accounts.ts"
import { BackButton, Screen } from "../AppShell.tsx"
import {
  type DeviceSession,
  changePassword,
  endSession,
  identities,
  sessions,
  unlinkIdentity,
} from "./api.ts"
import { signOutOf } from "./Settings.tsx"

const message = (error: unknown) =>
  error instanceof Error ? error.message : "Something went wrong. Try again."

/** One server's account: which series sites show, where you're signed in, and your password. */
export function AccountSettings() {
  const params = useParams({ from: "/app/settings/$server" })
  const navigate = useNavigate()
  const account = () => accountByKey(params().server)
  const toSettings = () => void navigate({ to: "/settings" })

  return (
    <Screen
      title={account() ? host(account()!.server) : "Server"}
      lead={
        account() && (
          <>
            {account()!.user.name}
            {account()!.user.role === "admin" ? ", admin" : ""}
          </>
        )
      }
      back={<BackButton label="Settings" fallback={toSettings} />}
      narrow
    >
      <Switch>
        <Match when={!account()}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>You're not signed in to this server. Add it in Settings.</p>
          </Alert>
        </Match>
        <Match when={account()?.expired}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>This server signed you out. Sign in again from Settings to change your account.</p>
          </Alert>
        </Match>
        <Match when={account()} keyed>
          {(current) => (
            <div class="grid gap-12">
              <Section
                title="Content"
                detail="Which series sites show you when you browse and search them."
              >
                <ContentRatingsForm
                  session={current}
                  savedText="Saved. Sites show the change the next time you open one."
                  onUnauthorized={() => expire(current.server)}
                />
              </Section>
              <Devices account={current} />
              <Show when={!current.user.demo}>
                <Password account={current} />
                <Identities account={current} />
              </Show>
              <div class="border-t pt-6">
                <Button
                  variant="outline"
                  class="text-destructive"
                  onClick={() => void signOutOf(current.server).then(toSettings)}
                >
                  Sign out of this server
                </Button>
              </div>
            </div>
          )}
        </Match>
      </Switch>
    </Screen>
  )
}

function Section(props: { title: string; detail?: string; children: JSX.Element }) {
  return (
    <section>
      <h2 class="mb-1 text-sm font-semibold">{props.title}</h2>
      <Show when={props.detail}>
        <p class="mb-3 text-[15px] text-muted-foreground">{props.detail}</p>
      </Show>
      {props.children}
    </section>
  )
}

const shortList = 5

const dates = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" })

function lastUsed(session: DeviceSession): string {
  if (session.current) return "This browser"
  const days = (Date.now() - Date.parse(session.lastUsedAt)) / 86_400_000
  // Servers note use at most once an hour, so recent use reads as today.
  if (days < 1) return "Used today"
  return `Last used ${dates.format(new Date(session.lastUsedAt))}`
}

/** Every device signed in to the account, with a way to sign each other one out. */
function Devices(props: { account: Account }) {
  const [list, { refetch }] = createResource(() => sessions(props.account))
  const [ending, setEnding] = createSignal<number>()
  const [failure, setFailure] = createSignal<string>()
  const [all, setAll] = createSignal(false)
  const others = () => (list() ?? []).filter((session) => !session.current)
  // Sign-ins pile up, one per browser and app, so the list starts short.
  const shown = () => {
    const items = list() ?? []
    return all() ? items : items.slice(0, shortList)
  }

  const endOthers = async () => {
    setEnding(-1)
    setFailure(undefined)
    try {
      await Promise.all(others().map((session) => endSession(props.account, session.id)))
    } catch (error) {
      setFailure(message(error))
    } finally {
      await refetch()
      setEnding(undefined)
    }
  }

  const end = async (session: DeviceSession) => {
    setEnding(session.id)
    setFailure(undefined)
    try {
      await endSession(props.account, session.id)
      await refetch()
    } catch (error) {
      setFailure(message(error))
    } finally {
      setEnding(undefined)
    }
  }

  return (
    <Section
      title="Devices"
      detail={
        props.account.user.demo
          ? "The demo shows only this browser, since other visitors share its account."
          : "Where you're signed in. Sign out a device you no longer use or have lost."
      }
    >
      <Switch>
        <Match when={list.error}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{message(list.error)}</p>
          </Alert>
        </Match>
        <Match when={list()}>
          <>
            <ul class="divide-y border-y">
              <For each={shown()}>
                {(session) => (
                  <li class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 py-4">
                    <div class="min-w-0">
                      <p class="flex items-center gap-2 font-semibold">
                        <span class="truncate">{session.device ?? "Unnamed device"}</span>
                        <Show when={session.current}>
                          <Badge variant="butter">This browser</Badge>
                        </Show>
                      </p>
                      <p class="mt-0.5 text-[15px] text-muted-foreground">
                        {session.current
                          ? `Signed in ${dates.format(new Date(session.createdAt))}`
                          : lastUsed(session)}
                      </p>
                    </div>
                    <Show when={!session.current && !props.account.user.demo}>
                      <Button
                        variant="ghost"
                        size="sm"
                        class="text-destructive"
                        disabled={ending() !== undefined}
                        onClick={() => void end(session)}
                      >
                        <Show when={ending() === session.id}>
                          <Spinner />
                        </Show>
                        Sign out
                      </Button>
                    </Show>
                  </li>
                )}
              </For>
            </ul>
            <div class="mt-4 flex flex-wrap gap-2">
              <Show when={!all() && (list()?.length ?? 0) > shortList}>
                <Button variant="outline" size="sm" onClick={() => setAll(true)}>
                  Show all {list()?.length}
                </Button>
              </Show>
              <Show when={others().length > 1 && !props.account.user.demo}>
                <Button
                  variant="outline"
                  size="sm"
                  class="text-destructive"
                  disabled={ending() !== undefined}
                  onClick={() => void endOthers()}
                >
                  <Show when={ending() === -1}>
                    <Spinner />
                  </Show>
                  Sign out every other device
                </Button>
              </Show>
            </div>
          </>
        </Match>
        <Match when={true}>
          <div class="grid gap-3 border-y py-4" aria-busy="true">
            <Skeleton class="h-5 w-48" />
            <Skeleton class="h-4 w-32" />
          </div>
        </Match>
      </Switch>
      <Show when={failure()}>
        <Alert variant="destructive" class="mt-4">
          <AlertCircle />
          <p>{failure()}</p>
        </Alert>
      </Show>
    </Section>
  )
}

/** Changing the password, which signs every other device out. */
function Password(props: { account: Account }) {
  const [busy, setBusy] = createSignal(false)
  const [status, setStatus] = createSignal<{ text: string; saved: boolean }>()

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    const form = event.currentTarget as HTMLFormElement
    const data = new FormData(form)
    const current = String(data.get("current") ?? "")
    const next = String(data.get("new") ?? "")
    if (next !== String(data.get("confirm") ?? "")) {
      setStatus({ text: "The new passwords don't match.", saved: false })
      return
    }
    setBusy(true)
    setStatus(undefined)
    try {
      await changePassword(props.account, current || undefined, next)
      form.reset()
      setStatus({
        text: "Your password is changed, and your other devices are signed out.",
        saved: true,
      })
    } catch (error) {
      setStatus({ text: message(error), saved: false })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Section title="Password" detail="Changing it signs out every other device.">
      <form class="grid gap-4" onSubmit={(event) => void submit(event)}>
        <Label>
          Current password
          <Input name="current" type="password" autocomplete="current-password" />
        </Label>
        <Label>
          New password
          <Input name="new" type="password" autocomplete="new-password" minLength={8} required />
        </Label>
        <Label>
          New password again
          <Input
            name="confirm"
            type="password"
            autocomplete="new-password"
            minLength={8}
            required
          />
        </Label>
        <p class="text-sm text-muted-foreground">
          At least 8 characters. If you've only signed in with another service, leave the current
          password empty.
        </p>
        <Show when={status()}>
          {(shown) => (
            <Alert variant={shown().saved ? "success" : "destructive"} role="status">
              {shown().saved ? <CheckCircle /> : <AlertCircle />}
              <p>{shown().text}</p>
            </Alert>
          )}
        </Show>
        <Button type="submit" class="w-full sm:w-auto sm:justify-self-start" disabled={busy()}>
          <Show when={busy()}>
            <Spinner />
          </Show>
          Change password
        </Button>
      </form>
    </Section>
  )
}

/** The services the account signs in with, when it has any. */
function Identities(props: { account: Account }) {
  const [list, { refetch }] = createResource(() => identities(props.account))
  const [failure, setFailure] = createSignal<string>()

  const unlink = async (provider: string) => {
    setFailure(undefined)
    try {
      await unlinkIdentity(props.account, provider)
      await refetch()
    } catch (error) {
      setFailure(message(error))
    }
  }

  return (
    <Show when={(list()?.length ?? 0) > 0}>
      <Section title="Sign-in services" detail="Services you can sign in to this server with.">
        <ul class="divide-y border-y">
          <For each={list()}>
            {(identity) => (
              <li class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 py-4">
                <div class="min-w-0">
                  <p class="truncate font-semibold">{identity.provider}</p>
                  <p class="mt-0.5 truncate text-[15px] text-muted-foreground">{identity.name}</p>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  class="text-destructive"
                  onClick={() => void unlink(identity.provider)}
                >
                  Unlink
                </Button>
              </li>
            )}
          </For>
        </ul>
        <Show when={failure()}>
          <Alert variant="destructive" class="mt-4">
            <AlertCircle />
            <p>{failure()}</p>
          </Alert>
        </Show>
      </Section>
    </Show>
  )
}
