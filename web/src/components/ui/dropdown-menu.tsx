import type { Component, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import * as DropdownMenuPrimitive from "@kobalte/core/dropdown-menu"
import type { PolymorphicProps } from "@kobalte/core/polymorphic"

import { cn } from "../../lib/cn.ts"

// solid-ui's dropdown menu: a list of actions beside the button that opens
// it. Kobalte moves focus through it with the arrow keys and closes it on
// Escape. It fades in with a slight scale, as the popover does.

const DropdownMenuTrigger = DropdownMenuPrimitive.Trigger

const DropdownMenu: Component<DropdownMenuPrimitive.DropdownMenuRootProps> = (props) => {
  return <DropdownMenuPrimitive.Root gutter={4} {...props} />
}

type DropdownMenuContentProps<T extends ValidComponent = "div"> =
  DropdownMenuPrimitive.DropdownMenuContentProps<T> & {
    class?: string | undefined
  }

const DropdownMenuContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, DropdownMenuContentProps<T>>,
) => {
  const [, rest] = splitProps(props as DropdownMenuContentProps, ["class"])
  return (
    <DropdownMenuPrimitive.Portal>
      <DropdownMenuPrimitive.Content
        class={cn(
          "z-50 min-w-56 origin-[var(--kb-menu-content-transform-origin)] overflow-hidden rounded-xl border bg-popover p-1 text-popover-foreground shadow-lg outline-none data-[closed]:animate-out data-[closed]:fade-out-0 data-[closed]:zoom-out-98 data-[expanded]:animate-in data-[expanded]:fade-in-0 data-[expanded]:zoom-in-98",
          props.class,
        )}
        {...rest}
      />
    </DropdownMenuPrimitive.Portal>
  )
}

type DropdownMenuItemProps<T extends ValidComponent = "div"> =
  DropdownMenuPrimitive.DropdownMenuItemProps<T> & {
    class?: string | undefined
  }

const DropdownMenuItem = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, DropdownMenuItemProps<T>>,
) => {
  const [, rest] = splitProps(props as DropdownMenuItemProps, ["class"])
  return (
    <DropdownMenuPrimitive.Item
      class={cn(
        "relative flex cursor-default items-center justify-between gap-3 rounded-lg px-2.5 py-2 text-[14px] outline-none select-none data-[disabled]:pointer-events-none data-[disabled]:opacity-50 data-[highlighted]:bg-muted",
        props.class,
      )}
      {...rest}
    />
  )
}

export { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem }
