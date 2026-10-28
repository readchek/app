import type { JSX, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as SelectPrimitive from "@kobalte/core/select"

import { cn } from "../../lib/cn.ts"
import { labelVariants } from "./text-field.tsx"

// solid-ui's select in Chek's shape: a round button that opens a list over
// the page, which fades in rather than sliding.

const Select = SelectPrimitive.Root
const SelectValue = SelectPrimitive.Value
const SelectHiddenSelect = SelectPrimitive.HiddenSelect

type SelectTriggerProps<T extends ValidComponent = "button"> =
  SelectPrimitive.SelectTriggerProps<T> & {
    class?: string | undefined
    children?: JSX.Element
  }

const SelectTrigger = <T extends ValidComponent = "button">(
  props: PolymorphicProps<T, SelectTriggerProps<T>>,
) => {
  const [local, others] = splitProps(props as SelectTriggerProps, ["class", "children"])
  return (
    <SelectPrimitive.Trigger
      class={cn(
        "flex h-10 w-full items-center justify-between gap-2 rounded-full border border-input bg-card px-4 text-sm font-semibold transition-colors hover:bg-accent focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50 [&>span]:truncate",
        local.class,
      )}
      {...others}
    >
      {local.children}
      <SelectPrimitive.Icon class="shrink-0 text-muted-foreground">
        <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
          <path
            d="m7 10 5 5 5-5"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
  )
}

type SelectContentProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectContentProps<T> & { class?: string | undefined }

const SelectContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectContentProps<T>>,
) => {
  const [local, others] = splitProps(props as SelectContentProps, ["class"])
  return (
    <SelectPrimitive.Portal>
      <SelectPrimitive.Content
        class={cn(
          "relative z-50 max-h-80 min-w-[var(--kb-popper-anchor-width)] origin-[var(--kb-select-content-transform-origin)] overflow-y-auto rounded-2xl border bg-popover p-1.5 text-popover-foreground shadow-xl data-[closed]:animate-out data-[closed]:fade-out-0 data-[closed]:zoom-out-98 data-[expanded]:animate-in data-[expanded]:fade-in-0 data-[expanded]:zoom-in-98",
          local.class,
        )}
        {...others}
      >
        <SelectPrimitive.Listbox class="m-0 outline-none" />
      </SelectPrimitive.Content>
    </SelectPrimitive.Portal>
  )
}

type SelectItemProps<T extends ValidComponent = "li"> = SelectPrimitive.SelectItemProps<T> & {
  class?: string | undefined
  children?: JSX.Element
}

const SelectItem = <T extends ValidComponent = "li">(
  props: PolymorphicProps<T, SelectItemProps<T>>,
) => {
  const [local, others] = splitProps(props as SelectItemProps, ["class", "children"])
  return (
    <SelectPrimitive.Item
      class={cn(
        "relative flex w-full cursor-pointer items-center justify-between gap-3 rounded-lg px-3 py-2 text-[15px] outline-none select-none data-[disabled]:pointer-events-none data-[disabled]:opacity-50 data-[highlighted]:bg-accent data-[highlighted]:text-accent-foreground",
        local.class,
      )}
      {...others}
    >
      <SelectPrimitive.ItemLabel>{local.children}</SelectPrimitive.ItemLabel>
      <SelectPrimitive.ItemIndicator class="text-link">
        <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
          <path
            d="m5 12.5 4.5 4.5L19 7.5"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </SelectPrimitive.ItemIndicator>
    </SelectPrimitive.Item>
  )
}

type SelectLabelProps<T extends ValidComponent = "label"> = SelectPrimitive.SelectLabelProps<T> & {
  class?: string | undefined
}

const SelectLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, SelectLabelProps<T>>,
) => {
  const [local, others] = splitProps(props as SelectLabelProps, ["class"])
  return <SelectPrimitive.Label class={cn(labelVariants(), local.class)} {...others} />
}

type SelectDescriptionProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectDescriptionProps<T> & {
    class?: string | undefined
  }

const SelectDescription = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectDescriptionProps<T>>,
) => {
  const [local, others] = splitProps(props as SelectDescriptionProps, ["class"])
  return (
    <SelectPrimitive.Description
      class={cn(labelVariants({ variant: "description" }), local.class)}
      {...others}
    />
  )
}

type SelectErrorMessageProps<T extends ValidComponent = "div"> =
  SelectPrimitive.SelectErrorMessageProps<T> & {
    class?: string | undefined
  }

const SelectErrorMessage = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SelectErrorMessageProps<T>>,
) => {
  const [local, others] = splitProps(props as SelectErrorMessageProps, ["class"])
  return (
    <SelectPrimitive.ErrorMessage
      class={cn(labelVariants({ variant: "error" }), local.class)}
      {...others}
    />
  )
}

export {
  Select,
  SelectValue,
  SelectHiddenSelect,
  SelectTrigger,
  SelectContent,
  SelectItem,
  SelectLabel,
  SelectDescription,
  SelectErrorMessage,
}
