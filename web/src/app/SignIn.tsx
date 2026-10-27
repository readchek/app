import { Show, createSignal, onMount } from "solid-js"
import { useNavigate, useSearch } from "@tanstack/solid-router"
import {
  ApiError,
  type Session,
  bundled,
  demoAccount,
  demoServer,
  openLink,
  serverAddress,
  signIn,
  signInToDemo,
} from "../api.ts"
import { Page } from "../components/Page.tsx"
import { AlertCircle, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button } from "../components/ui/button.tsx"
import { Input, Label } from "../components/ui/input.tsx"
import { addAccount } from "./accounts.ts"
import { Screen } from "./AppShell.tsx"

// demo.chek.page serves this build itself, and its account's password is
// public, so visitors find the form filled in and only press Sign in.
const demo = bundled && location.origin === demoServer

function message(error: unknown): string {
  return error instanceof Error ? error.message : "Something went wrong. Try again."
}

/** The first screen, before any server is signed in. */
export function Welcome() {
  return (
    <Page
      title="Welcome to Chek"
      lead={
        demo
          ? "This is the Chek demo. Its account is filled in, so sign in to look around."
          : "Read the books and comics your Chek server shares with you."
      }
    >
      <SignInForm />
    </Page>
  )
}

/** Signs in to one more server, from Settings. */
export function AddServer() {
  return (
    <Screen title="Add a server" narrow>
      <SignInForm />
    </Screen>
  )
}

function SignInForm() {
  const search = useSearch({ strict: false }) as () => { server?: string }
  const navigate = useNavigate()
  const [error, setError] = createSignal("")
  const [busy, setBusy] = createSignal(false)

  const run = async (signingIn: () => Promise<Session>) => {
    setBusy(true)
    setError("")
    try {
      addAccount(await signingIn())
      void navigate({ to: "/" })
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  onMount(() => {
    // The iOS app's link carries a one-time code in the fragment. It's
    // taken out of the address at once, so it isn't left in history.
    const code = new URLSearchParams(location.hash.slice(1)).get("code")
    const server = search().server
    if (!code || !server) return
    history.replaceState(history.state, "", location.pathname + location.search)
    void run(async () => {
      try {
        return await openLink(serverAddress(server), code)
      } catch (failure) {
        throw failure instanceof ApiError && failure.status === 400
          ? new Error("This link has expired or was already used. Sign in below instead.")
          : failure
      }
    })
  })

  const submit = (event: SubmitEvent) => {
    event.preventDefault()
    const form = new FormData(event.currentTarget as HTMLFormElement)
    void run(() =>
      signIn(
        bundled ? location.origin : serverAddress(String(form.get("server"))),
        String(form.get("name")).trim(),
        String(form.get("password")),
      ),
    )
  }

  return (
    <div class="grid gap-8">
      <form class="grid gap-4" onSubmit={submit}>
        <Show when={!bundled}>
          <Label>
            Server address
            <Input
              name="server"
              value={search().server ?? ""}
              placeholder="chek.example.com"
              autocomplete="url"
              inputmode="url"
              autocapitalize="off"
              spellcheck={false}
              required
            />
          </Label>
        </Show>
        <Label>
          Name
          <Input
            name="name"
            value={demo ? demoAccount.name : ""}
            autocomplete="username"
            autocapitalize="off"
            required
          />
        </Label>
        <Label>
          Password
          <Input
            name="password"
            type="password"
            value={demo ? demoAccount.password : ""}
            autocomplete="current-password"
            required
          />
        </Label>
        <Show when={error()}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{error()}</p>
          </Alert>
        </Show>
        <Button
          type="submit"
          class="mt-2 w-full sm:w-auto sm:justify-self-start sm:px-8"
          disabled={busy()}
        >
          <Show when={busy()}>
            <Spinner />
          </Show>
          Sign in
        </Button>
        <Show when={!demo}>
          <p class="text-sm text-muted-foreground">
            If you sign in to Chek with another service, set a password in the Chek app first.
          </p>
        </Show>
      </form>
      <Show when={!bundled}>
        <p class="border-t pt-6 text-[15px] text-muted-foreground">
          No server of your own?{" "}
          <Button
            variant="link"
            size="inline"
            disabled={busy()}
            onClick={() => void run(signInToDemo)}
          >
            Try the demo
          </Button>
        </p>
      </Show>
    </div>
  )
}
