import { Match, Show, Switch, createSignal } from "solid-js"
import { Link, useNavigate, useSearch } from "@tanstack/solid-router"
import { AlertCircle, Spinner } from "../components/icons.tsx"
import { Alert } from "../components/ui/alert.tsx"
import { Button, buttonVariants } from "../components/ui/button.tsx"
import { Checkbox, CheckboxLabel } from "../components/ui/checkbox.tsx"
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
            <RadioGroupItem value="folder">
              <RadioGroupItemLabel>A folder on this server</RadioGroupItemLabel>
              <RadioGroupItemDescription>
                EPUB, PDF, CBZ, CBR and more, in folders the server can read.
              </RadioGroupItemDescription>
            </RadioGroupItem>
            <RadioGroupItem value="komga">
              <RadioGroupItemLabel>A Komga server</RadioGroupItemLabel>
              <RadioGroupItemDescription>
                Read what one Komga account sees. Komga keeps the files.
              </RadioGroupItemDescription>
            </RadioGroupItem>
            <RadioGroupItem value="kavita">
              <RadioGroupItemLabel>A Kavita server</RadioGroupItemLabel>
              <RadioGroupItemDescription>
                Read what one Kavita account sees. Kavita keeps the files.
              </RadioGroupItemDescription>
            </RadioGroupItem>
          </div>
        </RadioGroup>

        <div class="grid gap-4">
          <Switch>
            <Match when={kind() === "folder"}>
              <TextField name="path" value={path()} onChange={setPath} required>
                <TextFieldLabel>Folder</TextFieldLabel>
                <span class="flex gap-2">
                  <TextFieldInput
                    placeholder="/books"
                    autocapitalize="off"
                    spellcheck={false}
                    class="font-mono text-[15px]"
                    dir="ltr"
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
                <TextFieldDescription>
                  The path on the server. With Docker, the path inside the container.
                </TextFieldDescription>
              </TextField>
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
              <TextField name="url" required>
                <TextFieldLabel>{source()} address</TextFieldLabel>
                <TextFieldInput
                  type="url"
                  placeholder={
                    kind() === "komga" ? "https://komga.example.com" : "https://kavita.example.com"
                  }
                  autocapitalize="off"
                  spellcheck={false}
                />
                <TextFieldDescription>
                  As the Chek server reaches it, such as http://komga:25600 on the same Docker
                  network.
                </TextFieldDescription>
              </TextField>
              <Show
                when={kind() === "komga"}
                fallback={
                  <TextField name="apiKey" required>
                    <TextFieldLabel>API key</TextFieldLabel>
                    <TextFieldInput autocomplete="off" spellcheck={false} />
                    <TextFieldDescription>
                      From the account's settings page in Kavita. The account needs the download
                      role.
                    </TextFieldDescription>
                  </TextField>
                }
              >
                <RadioGroup
                  value={komgaSignIn()}
                  onChange={(value) => setKomgaSignIn(value as KomgaSignIn)}
                >
                  <RadioGroupLabel class="mb-1">Sign in to Komga with</RadioGroupLabel>
                  <div class="divide-y border-y">
                    <RadioGroupItem value="key">
                      <RadioGroupItemLabel>An API key</RadioGroupItemLabel>
                      <RadioGroupItemDescription>
                        Made in Komga's account settings.
                      </RadioGroupItemDescription>
                    </RadioGroupItem>
                    <RadioGroupItem value="password">
                      <RadioGroupItemLabel>Email and password</RadioGroupItemLabel>
                      <RadioGroupItemDescription>
                        Use an account made for Chek.
                      </RadioGroupItemDescription>
                    </RadioGroupItem>
                  </div>
                </RadioGroup>
                <Show
                  when={komgaSignIn() === "password"}
                  fallback={
                    <TextField name="apiKey" required>
                      <TextFieldLabel>API key</TextFieldLabel>
                      <TextFieldInput autocomplete="off" spellcheck={false} />
                    </TextField>
                  }
                >
                  <TextField name="username" required>
                    <TextFieldLabel>Email</TextFieldLabel>
                    <TextFieldInput type="email" autocomplete="off" />
                  </TextField>
                  <TextField name="password" required>
                    <TextFieldLabel>Password</TextFieldLabel>
                    <TextFieldInput type="password" autocomplete="off" />
                  </TextField>
                </Show>
                <p class="text-sm text-muted-foreground">
                  The account needs Komga's page streaming and file download roles. Chek keeps these
                  details on the server and never shows them again.
                </p>
              </Show>
            </Match>
          </Switch>
          <TextField name="name" value={name()} onChange={setName} required>
            <TextFieldLabel>Name</TextFieldLabel>
            <TextFieldInput placeholder={kind() === "folder" ? "Comics" : source()} />
            <TextFieldDescription>What readers see this library called.</TextFieldDescription>
          </TextField>
          <Show when={kind() !== "folder"}>
            <Checkbox checked={writeProgress()} onChange={setWriteProgress} class="mt-2">
              <CheckboxLabel>
                Write my reading progress back to {source()}, so its own apps resume where Chek left
                off.
              </CheckboxLabel>
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
