import { Show, createSignal, onCleanup } from "solid-js"
import { AlertCircle, Spinner } from "../../components/icons.tsx"
import { Alert } from "../../components/ui/alert.tsx"
import { Button } from "../../components/ui/button.tsx"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../../components/ui/dialog.tsx"
import { TextField, TextFieldInput, TextFieldLabel } from "../../components/ui/text-field.tsx"
import type { Account } from "../accounts.ts"
import { loadLiveImage } from "../images.ts"
import { browserFramePath, clickBrowser, closeBrowser, resumeBrowser, startBrowser } from "./api.ts"
import { siteHost } from "./titles.ts"

// The server's browser is 1280 by 960, and clicks are sent in its pixels.
const frameWidth = 1280
const frameHeight = 960
// Often enough to follow a challenge's animation without flooding the server.
const frameEvery = 1000

/**
 * Opens a site in the browser the Chek server runs for you, so you can
 * pass a check such as Cloudflare's that the server can't pass alone. You
 * see it as pictures and click through them; the cookies it earns stay on
 * the server for the extension's next requests.
 */
export function Verify(props: {
  account: Account
  extensionId: string
  sites: string[]
  open: boolean
  onClose: (verified: boolean) => void
}) {
  const [address, setAddress] = createSignal(
    props.sites[0] ? `https://${siteHost(props.sites[0])}` : "https://",
  )
  const [phase, setPhase] = createSignal<"address" | "starting" | "open" | "finishing">("address")
  const [frame, setFrame] = createSignal<string>()
  const [error, setError] = createSignal<string>()
  let timer: ReturnType<typeof setTimeout> | undefined

  const showFrame = (url: string | undefined) => {
    const before = frame()
    setFrame(url)
    if (before) URL.revokeObjectURL(before)
  }

  const refresh = async () => {
    clearTimeout(timer)
    if (phase() !== "open") return
    try {
      const blob = await loadLiveImage(props.account, browserFramePath(props.extensionId))
      if (phase() === "open") showFrame(URL.createObjectURL(blob))
    } catch {
      // The browser lasts ten minutes; past that it's gone.
      setError("The browser closed. Open it again to carry on.")
      setPhase("address")
      return
    }
    timer = setTimeout(() => void refresh(), frameEvery)
  }

  const start = async () => {
    setError(undefined)
    setPhase("starting")
    try {
      await startBrowser(props.account, props.extensionId, address())
    } catch {
      // One browser at a time: one left open from before is closed and
      // the new one started.
      try {
        await closeBrowser(props.account, props.extensionId).catch(() => {})
        await startBrowser(props.account, props.extensionId, address())
      } catch (failure) {
        setError(failure instanceof Error ? failure.message : "The browser couldn't open.")
        setPhase("address")
        return
      }
    }
    setPhase("open")
    void refresh()
  }

  const click = (event: MouseEvent & { currentTarget: HTMLImageElement }) => {
    const box = event.currentTarget.getBoundingClientRect()
    const x = Math.round(((event.clientX - box.left) / box.width) * frameWidth)
    const y = Math.round(((event.clientY - box.top) / box.height) * frameHeight)
    void clickBrowser(
      props.account,
      props.extensionId,
      Math.min(Math.max(x, 0), frameWidth - 1),
      Math.min(Math.max(y, 0), frameHeight - 1),
    )
      .then(() => setTimeout(() => void refresh(), 300))
      .catch(() => {})
  }

  const finish = async (verified: boolean) => {
    clearTimeout(timer)
    const wasOpen = phase() === "open"
    setPhase("finishing")
    if (wasOpen) {
      // Resuming lets the extension use the browser's cookies; it doesn't
      // say the check passed, which only trying again shows.
      if (verified) await resumeBrowser(props.account, props.extensionId).catch(() => {})
      await closeBrowser(props.account, props.extensionId).catch(() => {})
    }
    showFrame(undefined)
    setPhase("address")
    props.onClose(verified)
  }

  onCleanup(() => {
    clearTimeout(timer)
    showFrame(undefined)
  })

  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) void finish(false)
      }}
    >
      <DialogContent class="max-w-3xl">
        <DialogHeader>
          <DialogTitle>Check you're a person</DialogTitle>
          <DialogDescription>
            Some sites check for a person before they answer. Your Chek server opens the site in its
            own browser, and you click through the check here. Then the site works again.
          </DialogDescription>
        </DialogHeader>

        <Show when={error()}>
          <Alert variant="destructive">
            <AlertCircle />
            <p>{error()}</p>
          </Alert>
        </Show>

        <Show
          when={phase() === "open" || phase() === "finishing"}
          fallback={
            <form
              class="grid gap-2"
              onSubmit={(event) => {
                event.preventDefault()
                void start()
              }}
            >
              <TextField value={address()} onChange={setAddress} required class="grid gap-2">
                <TextFieldLabel>Site address</TextFieldLabel>
                <div class="flex gap-3">
                  <TextFieldInput type="url" />
                  <Button type="submit" disabled={phase() === "starting"}>
                    <Show when={phase() === "starting"}>
                      <Spinner class="size-4" />
                    </Show>
                    Open
                  </Button>
                </div>
              </TextField>
            </form>
          }
        >
          <div class="overflow-hidden rounded-xl border bg-muted">
            <Show
              when={frame()}
              fallback={
                <div class="flex aspect-[4/3] items-center justify-center text-muted-foreground">
                  <Spinner class="size-5 text-link" />
                </div>
              }
            >
              {(src) => (
                <img
                  src={src()}
                  alt="The site in your server's browser. Click it as you would the site."
                  class="block aspect-[4/3] w-full cursor-pointer"
                  onClick={click}
                />
              )}
            </Show>
          </div>
        </Show>

        <DialogFooter>
          <Button variant="outline" onClick={() => void finish(false)}>
            Cancel
          </Button>
          <Button disabled={phase() !== "open"} onClick={() => void finish(true)}>
            Done
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
