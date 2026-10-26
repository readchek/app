import { type JSX, splitProps } from "solid-js"
import { Popover as PopoverPrimitive } from "@kobalte/core/popover"
import { cn } from "../../lib/cn.ts"

// After solid-ui's popover: a panel beside the button that opens it, which
// Kobalte keeps on screen, closes on Escape or a click outside, and labels.

export const Popover = PopoverPrimitive
export const PopoverTrigger = PopoverPrimitive.Trigger

export function PopoverContent(props: { class?: string; children: JSX.Element }) {
  const [local, rest] = splitProps(props, ["class", "children"])
  return (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Content
        class={cn(
          "z-50 max-h-[var(--kb-popper-content-available-height)] w-80 max-w-[calc(100vw-2rem)] origin-[var(--kb-popover-content-transform-origin)] overflow-y-auto rounded-2xl border bg-card p-5 text-card-foreground shadow-xl outline-none",
          local.class,
        )}
        {...rest}
      >
        {local.children}
      </PopoverPrimitive.Content>
    </PopoverPrimitive.Portal>
  )
}

export const PopoverTitle = (props: { class?: string; children: JSX.Element }) => (
  <PopoverPrimitive.Title class={cn("text-lg leading-tight tracking-[-0.02em]", props.class)}>
    {props.children}
  </PopoverPrimitive.Title>
)
