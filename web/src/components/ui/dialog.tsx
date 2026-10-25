import { type JSX, splitProps } from "solid-js"
import { Dialog as DialogPrimitive } from "@kobalte/core/dialog"
import { cn } from "../../lib/cn.ts"

// After solid-ui's dialog: Kobalte keeps focus inside, closes on Escape and
// gives the title and description to screen readers.

export const Dialog = DialogPrimitive

export function DialogContent(props: { class?: string; children: JSX.Element }) {
  const [local, rest] = splitProps(props, ["class", "children"])
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Overlay class="fixed inset-0 z-50 bg-foreground/30 backdrop-blur-[2px]" />
      <div class="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-6">
        <DialogPrimitive.Content
          class={cn(
            "relative grid max-h-[90dvh] w-full max-w-lg gap-6 overflow-y-auto rounded-t-3xl border bg-card p-6 text-card-foreground shadow-xl outline-none sm:rounded-3xl sm:p-8",
            local.class,
          )}
          {...rest}
        >
          {local.children}
          <DialogPrimitive.CloseButton
            aria-label="Close"
            class="absolute top-4 right-4 flex size-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none"
          >
            <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
              <path
                d="M6 6l12 12M18 6 6 18"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
              />
            </svg>
          </DialogPrimitive.CloseButton>
        </DialogPrimitive.Content>
      </div>
    </DialogPrimitive.Portal>
  )
}

export const DialogHeader = (props: { class?: string; children: JSX.Element }) => (
  <div class={cn("grid gap-2 pr-8", props.class)}>{props.children}</div>
)

export const DialogFooter = (props: { class?: string; children: JSX.Element }) => (
  <div class={cn("flex flex-col-reverse gap-3 sm:flex-row sm:justify-end", props.class)}>
    {props.children}
  </div>
)

export const DialogTitle = (props: { class?: string; children: JSX.Element }) => (
  <DialogPrimitive.Title class={cn("text-2xl leading-tight tracking-[-0.03em]", props.class)}>
    {props.children}
  </DialogPrimitive.Title>
)

export const DialogDescription = (props: { class?: string; children: JSX.Element }) => (
  <DialogPrimitive.Description
    class={cn("text-[15px] leading-snug text-muted-foreground", props.class)}
  >
    {props.children}
  </DialogPrimitive.Description>
)
