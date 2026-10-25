import { type JSX, splitProps } from "solid-js"
import { RadioGroup as RadioGroupPrimitive } from "@kobalte/core/radio-group"
import { cn } from "../../lib/cn.ts"

type RadioGroupProps = {
  class?: string
  value?: string
  onChange?: (value: string) => void
  disabled?: boolean
  name?: string
  children: JSX.Element
}

export function RadioGroup(props: RadioGroupProps) {
  const [local, rest] = splitProps(props, ["class"])
  return <RadioGroupPrimitive class={cn("grid gap-2.5", local.class)} {...rest} />
}

export const RadioGroupLabel = (props: { class?: string; children: JSX.Element }) => (
  <RadioGroupPrimitive.Label class={cn("text-sm font-semibold", props.class)}>
    {props.children}
  </RadioGroupPrimitive.Label>
)

/** A choice drawn as a card: its label, a line under it, and an optional mark before. */
export function RadioCard(props: {
  value: string
  title: JSX.Element
  description: JSX.Element
  leading?: JSX.Element
}) {
  return (
    <RadioGroupPrimitive.Item
      value={props.value}
      class="group relative flex items-center gap-3.5 rounded-2xl border bg-card p-3.5 transition-[background-color,border-color,box-shadow] has-[:focus-visible]:ring-3 has-[:focus-visible]:ring-ring/30 data-[checked]:border-link data-[checked]:bg-link/[0.06] data-[checked]:shadow-[inset_0_0_0_1px_var(--link)] data-[disabled]:cursor-default data-[disabled]:opacity-60 [&:not([data-disabled])]:cursor-pointer [&:not([data-disabled]):not([data-checked])]:hover:bg-muted/60 sm:p-4"
    >
      <RadioGroupPrimitive.ItemInput class="peer" />
      {props.leading}
      <span class="grid min-w-0 flex-1 gap-0.5">
        <RadioGroupPrimitive.ItemLabel class="cursor-[inherit] font-semibold after:absolute after:inset-0">
          {props.title}
        </RadioGroupPrimitive.ItemLabel>
        <RadioGroupPrimitive.ItemDescription class="text-[15px] leading-snug text-muted-foreground">
          {props.description}
        </RadioGroupPrimitive.ItemDescription>
      </span>
      <RadioGroupPrimitive.ItemControl class="flex size-[22px] shrink-0 items-center justify-center rounded-full border-2 border-input transition-colors group-data-[checked]:border-link group-data-[checked]:bg-link">
        <RadioGroupPrimitive.ItemIndicator class="size-2 rounded-full bg-card" />
      </RadioGroupPrimitive.ItemControl>
    </RadioGroupPrimitive.Item>
  )
}
