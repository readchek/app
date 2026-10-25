import type { JSX } from "solid-js"
import { Switch as SwitchPrimitive } from "@kobalte/core/switch"
import { cn } from "../../lib/cn.ts"

/** A setting that's on or off, drawn as a row: its label and a line under it, then the switch. After solid-ui's switch. */
export function Switch(props: {
  class?: string
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
  label: JSX.Element
  description?: JSX.Element
}) {
  return (
    <SwitchPrimitive
      checked={props.checked}
      onChange={props.onChange}
      disabled={props.disabled}
      class={cn(
        "group flex items-start justify-between gap-4 py-4 data-[disabled]:cursor-default [&:not([data-disabled])]:cursor-pointer",
        props.class,
      )}
    >
      <span class="grid min-w-0 gap-0.5">
        <SwitchPrimitive.Label class="cursor-[inherit] font-semibold">
          {props.label}
        </SwitchPrimitive.Label>
        {props.description && (
          <SwitchPrimitive.Description class="text-[15px] leading-snug text-muted-foreground">
            {props.description}
          </SwitchPrimitive.Description>
        )}
      </span>
      <SwitchPrimitive.Input class="peer" />
      <SwitchPrimitive.Control class="mt-0.5 inline-flex h-7 w-12 shrink-0 items-center rounded-full bg-input p-0.5 transition-colors peer-focus-visible:ring-3 peer-focus-visible:ring-ring/40 data-[checked]:bg-primary data-[disabled]:opacity-50">
        <SwitchPrimitive.Thumb class="size-6 rounded-full bg-background shadow-sm transition-transform data-[checked]:translate-x-5" />
      </SwitchPrimitive.Control>
    </SwitchPrimitive>
  )
}
