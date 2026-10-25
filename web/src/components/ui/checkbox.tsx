import type { JSX } from "solid-js"
import { Checkbox as CheckboxPrimitive } from "@kobalte/core/checkbox"
import { cn } from "../../lib/cn.ts"

export function Checkbox(props: {
  class?: string
  checked: boolean
  onChange: (checked: boolean) => void
  children: JSX.Element
}) {
  return (
    <CheckboxPrimitive
      checked={props.checked}
      onChange={props.onChange}
      class={cn("group flex cursor-pointer items-start gap-3", props.class)}
    >
      <CheckboxPrimitive.Input class="peer" />
      <CheckboxPrimitive.Control class="mt-px flex size-[22px] shrink-0 items-center justify-center rounded-md border-2 border-butter-foreground/40 bg-card text-primary-foreground transition-colors peer-focus-visible:ring-3 peer-focus-visible:ring-ring/40 data-[checked]:border-primary data-[checked]:bg-primary">
        <CheckboxPrimitive.Indicator>
          <svg viewBox="0 0 16 16" class="size-3.5" aria-hidden="true">
            <path
              d="m3.5 8.5 3 3 6-7"
              fill="none"
              stroke="currentColor"
              stroke-width="2.25"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </CheckboxPrimitive.Indicator>
      </CheckboxPrimitive.Control>
      <CheckboxPrimitive.Label class="cursor-pointer leading-snug">
        {props.children}
      </CheckboxPrimitive.Label>
    </CheckboxPrimitive>
  )
}
