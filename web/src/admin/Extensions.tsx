import { For, Match, Show, Switch, createSignal } from "solid-js"
import { createResource } from "../lib/resource.ts"
import { ApiError } from "../api.ts"
import { AlertCircle, CheckCircle, Lock, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button } from "../components/ui/button.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../components/ui/dialog.tsx"
import {
  TextField,
  TextFieldDescription,
  TextFieldInput,
  TextFieldLabel,
} from "../components/ui/text-field.tsx"
import {
  RadioGroup,
  RadioGroupItem,
  RadioGroupItemDescription,
  RadioGroupItemLabel,
  RadioGroupLabel,
} from "../components/ui/radio-group.tsx"
import { Skeleton } from "../components/ui/skeleton.tsx"
import {
  Switch as Toggle,
  SwitchControl as ToggleControl,
  SwitchDescription as ToggleDescription,
  SwitchLabel as ToggleLabel,
  SwitchThumb as ToggleThumb,
} from "../components/ui/switch.tsx"
import { Heading, adminSession } from "./AdminShell.tsx"
import { Section } from "./LibraryDetail.tsx"
import {
  type Credentials,
  type Repository,
  addRepository,
  deleteRepository,
  refreshRepository,
  repositories,
  settings,
  updateSettings,
} from "./api.ts"
import { ago, call, count, message } from "./util.ts"

type CredentialKind = "none" | "bearer" | "basic" | "header"

// What a private repository's answer says to ask for.
const asked: Record<string, CredentialKind> = {
  repository_needs_token: "bearer",
  repository_needs_password: "basic",
  repository_needs_credentials: "header",
}

export function Extensions() {
  const session = adminSession()
  const [list, { mutate, refetch }] = createResource(() => call(repositories(session)))
  const [policy, { mutate: setPolicy }] = createResource(() => call(settings(session)))
  const [policyError, setPolicyError] = createSignal("")
  const [removing, setRemoving] = createSignal<Repository>()

  const toggle = async (allowAnyRepository: boolean) => {
    setPolicyError("")
    try {
      setPolicy(await call(updateSettings(session, { allowAnyRepository })))
      // Whether people's own repositories are usable follows the switch.
      void refetch()
    } catch (failure) {
      setPolicyError(message(failure))
    }
  }

  const shared = () => list()?.filter((r) => r.allowListed) ?? []

  return (
    <>
      <Heading
        title="Extensions"
        lead="Repositories of sources people can browse and follow series from."
      />
      <div class="grid gap-10">
        <Switch>
          <Match when={list.error}>
            <Alert variant="destructive">
              <AlertCircle />
              <p>{message(list.error)}</p>
            </Alert>
          </Match>
          <Match when={list()}>
            <Show
              when={shared().length > 0}
              fallback={
                <p class="border-y py-6 text-[15px] leading-relaxed text-muted-foreground">
                  No repositories. Add the official one, chek.page/extensions, or one of your own.
                </p>
              }
            >
              <ul class="divide-y border-y">
                <For each={shared()}>
                  {(repository) => (
                    <RepositoryRow
                      repository={repository}
                      onRefreshed={(fresh) =>
                        mutate((items) => items?.map((r) => (r.id === fresh.id ? fresh : r)))
                      }
                      onRemove={() => setRemoving(repository)}
                    />
                  )}
                </For>
              </ul>
            </Show>
          </Match>
          <Match when={true}>
            <div aria-busy="true" class="divide-y border-y">
              <p class="sr-only" role="status">
                Loading…
              </p>
              <For each={[0, 1]}>
                {() => (
                  <div class="grid gap-2 py-4">
                    <Skeleton class="h-4 w-40" />
                    <Skeleton class="h-4 w-64" />
                  </div>
                )}
              </For>
            </div>
          </Match>
        </Switch>

        <AddRepository onAdded={(added) => mutate((items) => [...(items ?? []), added])} />

        <Section title="People's own repositories">
          <div class="border-y">
            <Toggle
              class="flex items-start justify-between gap-4 py-4 data-[disabled]:cursor-default [&:not([data-disabled])]:cursor-pointer"
              checked={policy()?.allowAnyRepository ?? false}
              disabled={!policy()}
              onChange={(on) => void toggle(on)}
            >
              <span class="grid min-w-0 gap-0.5">
                <ToggleLabel>Let people add any repository</ToggleLabel>
                <ToggleDescription>
                  Readers can add repositories only they see. Turning this off keeps them, but
                  nothing from them is installed or run.
                </ToggleDescription>
              </span>
              <ToggleControl class="mt-0.5">
                <ToggleThumb />
              </ToggleControl>
            </Toggle>
          </div>
          <Show when={policyError()}>
            <Alert variant="destructive">
              <AlertCircle />
              <p>{policyError()}</p>
            </Alert>
          </Show>
        </Section>
      </div>

      <Dialog open={removing() !== undefined} onOpenChange={(open) => !open && setRemoving()}>
        <DialogContent>
          <Show when={removing()}>
            {(repository) => (
              <RemoveRepository
                repository={repository()}
                onRemoved={() => {
                  mutate((items) => items?.filter((r) => r.id !== repository().id))
                  setRemoving()
                }}
                onCancel={() => setRemoving()}
              />
            )}
          </Show>
        </DialogContent>
      </Dialog>
    </>
  )
}

function RepositoryRow(props: {
  repository: Repository
  onRefreshed: (fresh: Repository) => void
  onRemove: () => void
}) {
  const session = adminSession()
  const [busy, setBusy] = createSignal(false)
  const [error, setError] = createSignal("")

  const refresh = async () => {
    setBusy(true)
    setError("")
    try {
      props.onRefreshed(await call(refreshRepository(session, props.repository.id)))
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  const host = () => {
    const url = new URL(props.repository.url)
    return url.host + url.pathname.replace(/\/index\.json$/, "")
  }

  return (
    <li class="grid gap-3 py-4">
      <div class="flex flex-wrap items-start gap-x-4 gap-y-3">
        <div class="grid min-w-0 flex-1 gap-0.5">
          <span class="flex items-center gap-2 font-semibold">
            <span class="truncate">{props.repository.name ?? host()}</span>
            <Show when={props.repository.hasCredentials}>
              <span class="text-muted-foreground [&>svg]:size-3.5" title="Private">
                <Lock />
              </span>
            </Show>
          </span>
          <span class="truncate text-[15px] text-muted-foreground" dir="ltr">
            {host()}
          </span>
          <span class="text-sm text-muted-foreground">
            {count(props.repository.extensionCount, "extension", "extensions")}
            <Show when={props.repository.fetchedAt}>
              {(fetched) => <> · checked {ago(fetched())}</>}
            </Show>
          </span>
        </div>
        <div class="flex gap-2">
          <Button variant="outline" size="sm" disabled={busy()} onClick={() => void refresh()}>
            <Show when={busy()}>
              <Spinner />
            </Show>
            Check now
          </Button>
          <Button variant="ghost" size="sm" class="text-destructive" onClick={props.onRemove}>
            Remove
          </Button>
        </div>
      </div>
      <Show when={error() || props.repository.fetchError}>
        <Alert variant="destructive">
          <AlertCircle />
          <p>
            {error() ||
              `The last check failed, so Chek keeps the extensions it found before: ${props.repository.fetchError}`}
          </p>
        </Alert>
      </Show>
    </li>
  )
}

function AddRepository(props: { onAdded: (added: Repository) => void }) {
  const session = adminSession()
  const [kind, setKind] = createSignal<CredentialKind>("none")
  const [status, setStatus] = createSignal<{ text: string; ok: boolean }>()
  const [busy, setBusy] = createSignal(false)

  const credentials = (form: FormData): Credentials | undefined => {
    const field = (key: string) => String(form.get(key) ?? "").trim()
    switch (kind()) {
      case "none":
        return undefined
      case "bearer":
        return { type: "bearer", token: field("token") }
      case "basic":
        return { type: "basic", username: field("username"), password: String(form.get("secret")) }
      case "header":
        return { type: "header", name: field("header"), value: field("value") }
    }
  }

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    const element = event.currentTarget as HTMLFormElement
    const form = new FormData(element)
    setBusy(true)
    setStatus(undefined)
    try {
      const added = await call(
        addRepository(session, String(form.get("url")).trim(), credentials(form)),
      )
      props.onAdded(added)
      element.reset()
      setKind("none")
      setStatus({
        text: `Added ${added.name ?? "the repository"}, with ${count(added.extensionCount, "extension", "extensions")}.`,
        ok: true,
      })
    } catch (failure) {
      // A private repository says what it needs, so the form asks for it.
      const needed = failure instanceof ApiError && failure.code ? asked[failure.code] : undefined
      if (needed && kind() === "none") setKind(needed)
      setStatus({ text: message(failure), ok: false })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Section title="Add a repository">
      <form class="grid gap-4" onSubmit={submit}>
        <TextField name="url" required>
          <TextFieldLabel>Address</TextFieldLabel>
          <TextFieldInput
            placeholder="chek.page/extensions or github:owner/repo"
            autocapitalize="off"
            spellcheck={false}
            dir="ltr"
          />
          <TextFieldDescription>
            Its index.json, the folder holding it, or a GitHub repository.
          </TextFieldDescription>
        </TextField>
        <RadioGroup value={kind()} onChange={(value) => setKind(value as CredentialKind)}>
          <RadioGroupLabel class="mb-1">Signing in</RadioGroupLabel>
          <div class="divide-y border-y">
            <RadioGroupItem value="none">
              <RadioGroupItemLabel>Public</RadioGroupItemLabel>
              <RadioGroupItemDescription>Anyone can read it.</RadioGroupItemDescription>
            </RadioGroupItem>
            <RadioGroupItem value="bearer">
              <RadioGroupItemLabel>Access token</RadioGroupItemLabel>
              <RadioGroupItemDescription>
                Such as a read-only GitHub token for a private repository.
              </RadioGroupItemDescription>
            </RadioGroupItem>
            <RadioGroupItem value="basic">
              <RadioGroupItemLabel>Username and password</RadioGroupItemLabel>
              <RadioGroupItemDescription>HTTP Basic.</RadioGroupItemDescription>
            </RadioGroupItem>
            <RadioGroupItem value="header">
              <RadioGroupItemLabel>A header</RadioGroupItemLabel>
              <RadioGroupItemDescription>Such as an API key.</RadioGroupItemDescription>
            </RadioGroupItem>
          </div>
        </RadioGroup>
        <Switch>
          <Match when={kind() === "bearer"}>
            <TextField name="token" required>
              <TextFieldLabel>Token</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="off" />
            </TextField>
          </Match>
          <Match when={kind() === "basic"}>
            <TextField name="username" required>
              <TextFieldLabel>Username</TextFieldLabel>
              <TextFieldInput autocomplete="off" autocapitalize="off" />
            </TextField>
            <TextField name="secret" required>
              <TextFieldLabel>Password</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="off" />
            </TextField>
          </Match>
          <Match when={kind() === "header"}>
            <TextField name="header" required>
              <TextFieldLabel>Header name</TextFieldLabel>
              <TextFieldInput placeholder="X-Api-Key" autocomplete="off" />
            </TextField>
            <TextField name="value" required>
              <TextFieldLabel>Value</TextFieldLabel>
              <TextFieldInput type="password" autocomplete="off" />
            </TextField>
          </Match>
        </Switch>
        <Show when={kind() !== "none"}>
          <p class="text-sm text-muted-foreground">
            Sent only to the repository's own address, and never shown again.
          </p>
        </Show>
        <Show when={status()}>
          {(shown) => (
            <Alert variant={shown().ok ? "success" : "destructive"} role="status">
              {shown().ok ? <CheckCircle /> : <AlertCircle />}
              <p>{shown().text}</p>
            </Alert>
          )}
        </Show>
        <Button
          type="submit"
          class="mt-2 w-full sm:w-auto sm:justify-self-start sm:px-8"
          disabled={busy()}
        >
          <Show when={busy()}>
            <Spinner />
          </Show>
          Add repository
        </Button>
      </form>
    </Section>
  )
}

function RemoveRepository(props: {
  repository: Repository
  onRemoved: () => void
  onCancel: () => void
}) {
  const session = adminSession()
  const [busy, setBusy] = createSignal(false)
  const [error, setError] = createSignal("")

  const remove = async () => {
    setBusy(true)
    setError("")
    try {
      await call(deleteRepository(session, props.repository.id))
      props.onRemoved()
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle>Remove {props.repository.name ?? "this repository"}?</DialogTitle>
        <DialogDescription>
          Everyone's extensions from it are uninstalled, and libraries that follow series through
          them stop syncing until they're installed again.
        </DialogDescription>
      </DialogHeader>
      <Show when={error()}>
        <Alert variant="destructive">
          <AlertCircle />
          <p>{error()}</p>
        </Alert>
      </Show>
      <DialogFooter>
        <Button variant="outline" onClick={props.onCancel}>
          Cancel
        </Button>
        <Button variant="destructive" disabled={busy()} onClick={() => void remove()}>
          <Show when={busy()}>
            <Spinner />
          </Show>
          Remove repository
        </Button>
      </DialogFooter>
    </>
  )
}
