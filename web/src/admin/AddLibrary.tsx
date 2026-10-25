import { Match, Show, Switch, createSignal } from "solid-js"
import { Link, useNavigate, useSearch } from "@tanstack/solid-router"
import { AlertCircle, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import { Checkbox } from "../components/ui/checkbox.tsx"
import { Input, Label } from "../components/ui/input.tsx"
import { RadioGroup, RadioGroupLabel, RadioRow } from "../components/ui/radio-group.tsx"
import { Heading, adminSession } from "./AdminShell.tsx"
import { FolderPicker } from "./FolderPicker.tsx"
import { type NewLibrary, addLibrary } from "./api.ts"
import { call, message } from "./util.ts"

type Kind = "folder" | "komga" | "kavita"
type KomgaSignIn = "key" | "password"

export function AddLibrary() {
  const session = adminSession()
  const navigate = useNavigate()
  const search = useSearch({ from: "/admin/libraries/new" })
  const [kind, setKind] = createSignal<Kind>("folder")
  const [komgaSignIn, setKomgaSignIn] = createSignal<KomgaSignIn>("key")
  const [name, setName] = createSignal("")
  const [path, setPath] = createSignal("")
  const [picking, setPicking] = createSignal(false)
  const [writeProgress, setWriteProgress] = createSignal(true)
  const [error, setError] = createSignal("")
  const [busy, setBusy] = createSignal(false)

  const source = () => (kind() === "komga" ? "Komga" : "Kavita")

  const library = (form: FormData): NewLibrary => {
    const field = (key: string) => String(form.get(key) ?? "").trim()
    switch (kind()) {
      case "folder":
        return { name: name().trim(), path: path().trim() }
      case "komga":
        return {
          name: name().trim(),
          komga: {
            url: field("url"),
            writeProgress: writeProgress(),
            ...(komgaSignIn() === "key"
              ? { apiKey: field("apiKey") }
              : { username: field("username"), password: String(form.get("password")) }),
          },
        }
      case "kavita":
        return {
          name: name().trim(),
          kavita: { url: field("url"), apiKey: field("apiKey"), writeProgress: writeProgress() },
        }
    }
  }

  const submit = async (event: SubmitEvent) => {
    event.preventDefault()
    setBusy(true)
    setError("")
    try {
      const added = await call(
        addLibrary(session, library(new FormData(event.currentTarget as HTMLFormElement))),
      )
      void navigate({
        to: "/admin/libraries/$libraryId",
        params: { libraryId: String(added.id) },
      })
    } catch (failure) {
      setError(message(failure))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <Show when={search().welcome}>
        <p class="mb-3 text-sm font-semibold text-link">Step 2 of 2</p>
      </Show>
      <Heading
        title="Add a library"
        lead={
          search().welcome
            ? "You're the server's admin. Now point Chek at your books and comics."
            : "Chek scans it for books and comics, and keeps it up to date."
        }
      />
      <form class="grid gap-8" onSubmit={submit}>
        <RadioGroup
          value={kind()}
          disabled={busy()}
          onChange={(value) => {
            setKind(value as Kind)
            setError("")
          }}
        >
          <RadioGroupLabel class="mb-1">Where your library is</RadioGroupLabel>
          <div class="divide-y border-y">
            <RadioRow
              value="folder"
              title="A folder on this server"
              description="EPUB, PDF, CBZ, CBR and more, in folders the server can read."
            />
            <RadioRow
              value="komga"
              title="A Komga server"
              description="Read what one Komga account sees. Komga keeps the files."
            />
            <RadioRow
              value="kavita"
              title="A Kavita server"
              description="Read what one Kavita account sees. Kavita keeps the files."
            />
          </div>
        </RadioGroup>

        <div class="grid gap-4">
          <Switch>
            <Match when={kind() === "folder"}>
              <Label>
                Folder
                <span class="flex gap-2">
                  <Input
                    name="path"
                    value={path()}
                    onInput={(e) => setPath(e.currentTarget.value)}
                    placeholder="/books"
                    autocapitalize="off"
                    spellcheck={false}
                    class="font-mono text-[15px]"
                    dir="ltr"
                    required
                  />
                  <Button
                    type="button"
                    variant="outline"
                    class="h-12 shrink-0"
                    onClick={() => setPicking(true)}
                  >
                    Browse
                  </Button>
                </span>
                <span class="text-sm font-normal text-muted-foreground">
                  The path on the server. With Docker, the path inside the container.
                </span>
              </Label>
              <FolderPicker
                open={picking()}
                onOpenChange={setPicking}
                start={path()}
                onPick={(picked) => {
                  setPath(picked)
                  if (!name().trim()) setName(picked.split("/").filter(Boolean).pop() ?? "")
                }}
              />
            </Match>
            <Match when={kind() !== "folder"}>
              <Label>
                {source()} address
                <Input
                  name="url"
                  type="url"
                  placeholder={
                    kind() === "komga" ? "https://komga.example.com" : "https://kavita.example.com"
                  }
                  autocapitalize="off"
                  spellcheck={false}
                  required
                />
                <span class="text-sm font-normal text-muted-foreground">
                  As the Chek server reaches it, such as http://komga:25600 on the same Docker
                  network.
                </span>
              </Label>
              <Show
                when={kind() === "komga"}
                fallback={
                  <Label>
                    API key
                    <Input name="apiKey" autocomplete="off" spellcheck={false} required />
                    <span class="text-sm font-normal text-muted-foreground">
                      From the account's settings page in Kavita. The account needs the download
                      role.
                    </span>
                  </Label>
                }
              >
                <RadioGroup
                  value={komgaSignIn()}
                  onChange={(value) => setKomgaSignIn(value as KomgaSignIn)}
                >
                  <RadioGroupLabel class="mb-1">Sign in to Komga with</RadioGroupLabel>
                  <div class="divide-y border-y">
                    <RadioRow
                      value="key"
                      title="An API key"
                      description="Made in Komga's account settings."
                    />
                    <RadioRow
                      value="password"
                      title="Email and password"
                      description="Use an account made for Chek."
                    />
                  </div>
                </RadioGroup>
                <Show
                  when={komgaSignIn() === "password"}
                  fallback={
                    <Label>
                      API key
                      <Input name="apiKey" autocomplete="off" spellcheck={false} required />
                    </Label>
                  }
                >
                  <Label>
                    Email
                    <Input name="username" type="email" autocomplete="off" required />
                  </Label>
                  <Label>
                    Password
                    <Input name="password" type="password" autocomplete="off" required />
                  </Label>
                </Show>
                <p class="text-sm text-muted-foreground">
                  The account needs Komga's page streaming and file download roles. Chek keeps these
                  details on the server and never shows them again.
                </p>
              </Show>
            </Match>
          </Switch>
          <Label>
            Name
            <Input
              name="name"
              value={name()}
              onInput={(e) => setName(e.currentTarget.value)}
              placeholder={kind() === "folder" ? "Comics" : source()}
              required
            />
            <span class="text-sm font-normal text-muted-foreground">
              What readers see this library called.
            </span>
          </Label>
          <Show when={kind() !== "folder"}>
            <Checkbox checked={writeProgress()} onChange={setWriteProgress} class="mt-2">
              Write my reading progress back to {source()}, so its own apps resume where Chek left
              off.
            </Checkbox>
          </Show>
        </div>

        <Show when={error()}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{error()}</p>
          </Alert>
        </Show>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <Button type="submit" class="w-full sm:w-auto sm:px-8" disabled={busy()}>
            <Show when={busy()}>
              <Spinner />
            </Show>
            {kind() === "folder" ? "Add library" : `Connect to ${source()}`}
          </Button>
          <Link
            to="/admin/libraries"
            class={buttonVariants({ variant: "ghost", class: "w-full sm:w-auto" })}
          >
            {search().welcome ? "Skip for now" : "Cancel"}
          </Link>
        </div>
      </form>
    </>
  )
}
