import type { Component, ComponentProps, JSX, ParentProps, VoidProps } from "solid-js"
import { splitProps } from "solid-js"

import * as DialogPrimitive from "@kobalte/core/dialog"
import * as CommandPrimitive from "cmdk-solid"

import { cn } from "../../lib/cn.ts"

// solid-ui's command menu, on cmdk-solid, in Chek's shape. Its dialog opens
// near the top of the window rather than in the middle, so the panel doesn't
// jump about as results arrive and the list grows.

const Command: Component<ParentProps<CommandPrimitive.CommandRootProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <CommandPrimitive.CommandRoot
      class={cn(
        "flex size-full flex-col overflow-hidden rounded-2xl bg-popover text-popover-foreground",
        local.class,
      )}
      {...others}
    />
  )
}

type CommandDialogProps = ParentProps<
  DialogPrimitive.DialogRootProps & {
    /** Read to screen readers as the dialog's name. */
    title: string
    commandProps?: CommandPrimitive.CommandRootProps
  }
>

const CommandDialog: Component<CommandDialogProps> = (props) => {
  const [local, others] = splitProps(props, ["children", "title", "commandProps"])

  return (
    <DialogPrimitive.Root {...others}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay class="fixed inset-0 z-50 bg-foreground/30 data-[closed]:animate-out data-[closed]:fade-out-0 data-[expanded]:animate-in data-[expanded]:fade-in-0" />
        <div class="fixed inset-0 z-50 flex items-start justify-center px-3 pt-[calc(0.75rem+env(safe-area-inset-top))] sm:px-6 sm:pt-[12vh]">
          <DialogPrimitive.Content class="w-full max-w-xl overflow-hidden rounded-2xl border bg-popover shadow-xl outline-none data-[closed]:animate-out data-[closed]:fade-out-0 data-[closed]:zoom-out-98 data-[expanded]:animate-in data-[expanded]:fade-in-0 data-[expanded]:zoom-in-98">
            <DialogPrimitive.Title class="sr-only">{local.title}</DialogPrimitive.Title>
            <Command
              class="[&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:text-muted-foreground [&_[cmdk-group]:not([hidden])_~[cmdk-group]]:pt-0"
              {...local.commandProps}
            >
              {local.children}
            </Command>
          </DialogPrimitive.Content>
        </div>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  )
}

const CommandInput: Component<VoidProps<CommandPrimitive.CommandInputProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <div class="flex items-center gap-2.5 border-b px-4" cmdk-input-wrapper="">
      <svg
        viewBox="0 0 24 24"
        class="size-[18px] shrink-0 text-muted-foreground"
        aria-hidden="true"
      >
        <circle cx="11" cy="11" r="6.5" fill="none" stroke="currentColor" stroke-width="2" />
        <path
          d="m16 16 4 4"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
        />
      </svg>
      <CommandPrimitive.CommandInput
        class={cn(
          "flex h-14 w-full bg-transparent text-[17px] outline-none placeholder:text-muted-foreground/70 disabled:cursor-not-allowed disabled:opacity-50",
          local.class,
        )}
        {...others}
      />
    </div>
  )
}

const CommandList: Component<ParentProps<CommandPrimitive.CommandListProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <CommandPrimitive.CommandList
      class={cn(
        "max-h-[min(28rem,calc(100dvh-8rem))] overflow-x-hidden overflow-y-auto overscroll-contain",
        local.class,
      )}
      {...others}
    />
  )
}

const CommandEmpty: Component<ParentProps<CommandPrimitive.CommandEmptyProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <CommandPrimitive.CommandEmpty
      class={cn("px-4 py-8 text-center text-[15px] text-muted-foreground", local.class)}
      {...others}
    />
  )
}

const CommandLoading: Component<ParentProps<CommandPrimitive.CommandLoadingProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <CommandPrimitive.CommandLoading
      class={cn("px-4 py-3 text-sm text-muted-foreground", local.class)}
      {...others}
    />
  )
}

const CommandGroup: Component<ParentProps<CommandPrimitive.CommandGroupProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <CommandPrimitive.CommandGroup
      class={cn(
        "overflow-hidden p-1.5 text-foreground [&_[cmdk-group-heading]]:px-2.5 [&_[cmdk-group-heading]]:pt-2 [&_[cmdk-group-heading]]:pb-1.5 [&_[cmdk-group-heading]]:text-xs [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:text-muted-foreground",
        local.class,
      )}
      {...others}
    />
  )
}

const CommandSeparator: Component<VoidProps<CommandPrimitive.CommandSeparatorProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return <CommandPrimitive.CommandSeparator class={cn("h-px bg-border", local.class)} {...others} />
}

const CommandItem: Component<ParentProps<CommandPrimitive.CommandItemProps>> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <CommandPrimitive.CommandItem
      cmdk-item=""
      class={cn(
        "relative flex cursor-pointer items-center gap-3 rounded-lg px-2.5 py-2 text-[15px] outline-none select-none aria-selected:bg-accent aria-selected:text-accent-foreground data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50 [&>svg]:size-[18px] [&>svg]:shrink-0 [&>svg]:text-muted-foreground",
        local.class,
      )}
      {...others}
    />
  )
}

const CommandShortcut: Component<ComponentProps<"span">> = (props) => {
  const [local, others] = splitProps(props, ["class"])

  return (
    <span
      class={cn("ms-auto text-xs tracking-widest text-muted-foreground", local.class)}
      {...others}
    />
  )
}

/** A key to press, as the palette's trigger shows ⌘K. */
const Kbd = (props: { class?: string; children: JSX.Element }) => (
  <kbd
    class={cn(
      "inline-flex h-5 items-center rounded border bg-muted px-1.5 font-sans text-[11px] font-semibold text-muted-foreground",
      props.class,
    )}
  >
    {props.children}
  </kbd>
)

export {
  Command,
  CommandDialog,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandLoading,
  CommandGroup,
  CommandItem,
  CommandShortcut,
  CommandSeparator,
  Kbd,
}
