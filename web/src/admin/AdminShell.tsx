import { For, type JSX, Match, Show, Switch, createResource, createSignal } from "solid-js"
import { Link, Outlet, useNavigate, useSearch } from "@tanstack/solid-router"
import { ApiError, type Session, bundled, serverAddress, signIn } from "../api.ts"
import { forget, remember, session } from "../session.ts"
import { Wordmark } from "../components/Wordmark.tsx"
import { AlertCircle, Lock, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Badge } from "../components/ui/badge.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import { Input, Label } from "../components/ui/input.tsx"
import { cn } from "../lib/cn.ts"
import { type ServerInfo, serverInfo, setUp } from "./api.ts"
import { message } from "./util.ts"

const sections = [
  { to: "/admin/libraries", label: "Libraries" },
  { to: "/admin/users", label: "People" },
  { to: "/admin/extensions", label: "Extensions" },
  { to: "/admin/settings", label: "Settings" },
] as const

// The server this tab last managed, so a return visit only asks to sign in.
const lastServerKey = "chek.admin.server"

function lastServer(): string {
  try {
    return localStorage.getItem(lastServerKey) ?? ""
  } catch {
    return ""
  }
}

function rememberServer(server: string) {
  try {
    localStorage.setItem(lastServerKey, server)
  } catch {
    // Storage can be refused; the address is only a convenience.
  }
}

/** The frame of every admin screen: the wordmark, the sections, and a column for the screen. */
function Frame(props: { nav?: boolean; children: JSX.Element }) {
  return (
    <div class="mx-auto flex min-h-dvh w-full max-w-2xl flex-col px-5 sm:px-6">
      <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-4 pt-6 sm:pt-10">
        <span class="flex items-center gap-2.5">
          <a href="https://chek.page" aria-label="Chek" class="inline-block text-link">
            <Wordmark />
          </a>
          <Badge variant="secondary">Admin</Badge>
        </span>
        <Show when={props.nav}>
          <nav aria-label="Admin" class="-mx-3 flex gap-1 overflow-x-auto sm:mx-0">
            <For each={sections}>
              {(section) => (
                <Link
                  to={section.to}
                  class={cn(
                    buttonVariants({ variant: "ghost", size: "sm" }),
                    "text-muted-foreground",
                  )}
                  activeProps={{ class: "bg-muted text-foreground", "aria-current": "page" }}
                >
                  {section.label}
                </Link>
              )}
            </For>
          </nav>
        </Show>
      </header>
      <main class="flex-1 pt-10 pb-16 sm:pt-14">{props.children}</main>
      <footer class="flex flex-wrap justify-between gap-x-6 gap-y-1 pb-8 text-sm text-muted-foreground">
        <span>For the love of the next chapter.</span>
        <span>
          <a class="hover:text-foreground" href="https://docs.chek.page">
            Docs
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

/** A screen's title and the line under it, in the type of the content settings page. */
export function Heading(props: { title: string; lead?: JSX.Element; children?: JSX.Element }) {
  return (
    <div class="mb-8 flex flex-wrap items-end justify-between gap-4">
      <div class="min-w-0">
        <h1 class="text-[40px] leading-none tracking-[-0.045em] sm:text-5xl">{props.title}</h1>
        {props.lead && (
          <p class="mt-3 text-[17px] leading-snug text-muted-foreground">{props.lead}</p>
        )}
      </div>
      {props.children}
    </div>
  )
}

/** The signed-in admin's session. Only screens inside the shell call it. */
export function adminSession(): Session {
  const current = session()
  if (!current) throw new Error("The admin screens need a session.")
  return current
}

export function AdminShell() {
  return (
    <Switch>
      <Match when={session()?.user.role === "admin"}>
        <Frame nav>
          <Outlet />
        </Frame>
      </Match>
      <Match when={session()}>
        {(current) => (
          <Frame>
            <Heading
              title="Admins only"
              lead="This account can read on the server, but not manage it."
            />
            <p class="flex flex-wrap items-center gap-x-1.5 text-[15px] text-muted-foreground">
              <span>
                Signed in as{" "}
                <strong class="font-semibold text-foreground">{current().user.name}</strong>.
              </span>
              <Button variant="link" size="inline" onClick={() => void forget()}>
                Sign in as someone else
              </Button>
            </p>
          </Frame>
        )}
      </Match>
      <Match when={true}>
        <Frame>
          <Welcome />
        </Frame>
      </Match>
    </Switch>
  )
}

/** Finds the server, then signs in, or claims a new server with its setup token. */
function Welcome() {
  const search = useSearch({ strict: false }) as () => { server?: string }
  const here = bundled ? location.origin : undefined
  const [server, setServer] = createSignal<string | undefined>(here)
  const [info] = createResource(server, serverInfo)
  const [error, setError] = createSignal("")

  const find = (event: SubmitEvent) => {
    event.preventDefault()
    setError("")
    const form = new FormData(event.currentTarget as HTMLFormElement)
    try {
      setServer(serverAddress(String(form.get("server"))))
    } catch (failure) {
      setError(message(failure))
    }
  }

  const failure = () => {
    const failed = info.error
    if (failed instanceof ApiError && failed.status === 404) {
      return "This server is older than the admin panel. Update Chek server to 0.4.0 or later, then try again."
    }
    return message(failed)
  }

  return (
    <Switch>
      <Match when={server() && info.loading}>
        <p role="status" class="flex items-center gap-2.5 text-muted-foreground">
          <Spinner class="size-[18px] text-link" />
          Connecting…
        </p>
      </Match>
      <Match when={server() ? info() : undefined}>
        {(found) =>
          found().setupRequired ? (
            <SetUp server={server()!} />
          ) : (
            <SignIn
              server={server()!}
              info={found()}
              onChange={here ? undefined : () => setServer()}
            />
          )
        }
      </Match>
      <Match when={true}>
        <Heading title="Admin" lead="Manage your Chek server's libraries, people and extensions." />
        <form class="grid gap-4" onSubmit={find}>
          <Label>
            Server address
            <Input
              name="server"
              value={search().server ?? lastServer()}
              placeholder="chek.example.com"
              autocomplete="url"
              inputmode="url"
              autocapitalize="off"
              spellcheck={false}
              required
            />
          </Label>
          <Show when={error() || (server() && info.error)}>
            <Alert variant="destructive">
              <AlertCircle />
              <p>{error() || failure()}</p>
            </Alert>
          </Show>
          <Button type="submit" class="mt-2 w-full sm:w-auto sm:justify-self-start sm:px-8">
            Continue
          </Button>
        </form>
        <p class="mt-8 border-t pt-6 text-[15px] leading-relaxed text-muted-foreground">
          The web app reaches servers with an https address. To manage a server on your home network
          without one, open its own admin page instead, such as{" "}
          <span class="font-semibold text-foreground">http://192.168.1.20:8080/admin</span>.
        </p>
      </Match>
    </Switch>
  )
}

function SignIn(props: { server: string; info: ServerInfo; onChange?: () => void }) {
  const [error, setError] = createSignal("")
  const [busy, setBusy] = createSignal(false)

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    const form = new FormData(event.currentTarget as HTMLFormElement)
    setBusy(true)
    setError("")
    try {
      remember(
        await signIn(props.server, String(form.get("name")).trim(), String(form.get("password"))),
      )
      rememberServer(props.server)
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <Heading title="Sign in" lead="Sign in with an admin account." />
      <p class="mb-6 flex flex-wrap items-center gap-x-1.5 text-[15px] text-muted-foreground">
        <span>
          Chek server {props.info.version} on{" "}
          <strong class="font-semibold text-foreground">{new URL(props.server).host}</strong>.
        </span>
        <Show when={props.onChange}>
          {(change) => (
            <Button variant="link" size="inline" onClick={() => change()()}>
              Change
            </Button>
          )}
        </Show>
      </p>
      <form class="grid gap-4" onSubmit={submit}>
        <Label>
          Name
          <Input name="name" autocomplete="username" autocapitalize="off" required />
        </Label>
        <Label>
          Password
          <Input name="password" type="password" autocomplete="current-password" required />
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
        <p class="text-sm text-muted-foreground">
          If you sign in to Chek with another service, set a password in the Chek app first.
        </p>
      </form>
    </>
  )
}

/** The first step of setting up a server: claiming it as its first admin. */
function SetUp(props: { server: string }) {
  const navigate = useNavigate()
  const [error, setError] = createSignal("")
  const [busy, setBusy] = createSignal(false)

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    const form = new FormData(event.currentTarget as HTMLFormElement)
    const password = String(form.get("password"))
    if (password !== String(form.get("confirm"))) {
      setError("The passwords don't match.")
      return
    }
    setBusy(true)
    setError("")
    try {
      const created = await setUp(
        props.server,
        String(form.get("token")).trim(),
        String(form.get("name")).trim(),
        password,
      )
      remember(created)
      rememberServer(props.server)
      void navigate({ to: "/admin/libraries/new", search: { welcome: true } })
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <p class="mb-3 text-sm font-semibold text-link">Step 1 of 2</p>
      <Heading
        title="Set up Chek"
        lead={<>Claim {new URL(props.server).host} by making its first admin account.</>}
      />
      <form class="grid gap-4" onSubmit={submit}>
        <Label>
          Setup token
          <Input
            name="token"
            autocomplete="off"
            autocapitalize="off"
            spellcheck={false}
            class="font-mono text-[15px]"
            required
          />
          <span class="text-sm font-normal text-muted-foreground">
            The server prints it in its log when it starts without accounts. With Docker, run{" "}
            <code class="rounded bg-muted px-1 py-0.5 text-[13px]">docker logs chek</code>. If you
            set <code class="rounded bg-muted px-1 py-0.5 text-[13px]">CHEK_SETUP_TOKEN</code>, use
            that.
          </span>
        </Label>
        <Label>
          Your name
          <Input name="name" autocomplete="username" autocapitalize="off" maxlength={64} required />
        </Label>
        <Label>
          Password
          <Input
            name="password"
            type="password"
            autocomplete="new-password"
            minlength={8}
            required
          />
          <span class="text-sm font-normal text-muted-foreground">At least 8 characters.</span>
        </Label>
        <Label>
          Password again
          <Input name="confirm" type="password" autocomplete="new-password" required />
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
          Create admin account
        </Button>
      </form>
      <Alert role="note" class="mt-8 border-t pt-6">
        <Lock />
        <p>
          Anyone who reaches this page before you can claim the server, but only with the token from
          its log.
        </p>
      </Alert>
    </>
  )
}
