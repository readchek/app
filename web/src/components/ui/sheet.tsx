import type { Component, ComponentProps, JSX, ValidComponent } from "solid-js"
import { Show, splitProps } from "solid-js"

import * as SheetPrimitive from "@kobalte/core/dialog"
import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import { type VariantProps, cva } from "class-variance-authority"

import { cn } from "../../lib/cn.ts"

// solid-ui's sheet: a panel along one edge of the screen, such as the
// trailing edge on a desktop or the bottom on a phone. It fades in with a
// short slide rather than solid-ui's long one. Kobalte keeps focus inside,
// closes on Escape and a click outside, and labels it from its title.
// Without its overlay, as a non-modal Sheet, it sits beside the page and
// everything else stays usable.

const Sheet = SheetPrimitive.Root
const SheetTrigger = SheetPrimitive.Trigger
const SheetClose = SheetPrimitive.CloseButton

const portalVariants = cva("fixed inset-0 z-50 flex", {
  variants: {
    position: {
      bottom: "items-end",
      right: "justify-end",
    },
  },
  defaultVariants: { position: "right" },
})

type PortalProps = SheetPrimitive.DialogPortalProps &
  VariantProps<typeof portalVariants> & { overlay?: boolean }

const SheetPortal: Component<PortalProps> = (props) => {
  const [local, others] = splitProps(props, ["position", "children", "overlay"])
  return (
    <SheetPrimitive.Portal {...others}>
      {/* Without an overlay, only the panel takes clicks; the page behind
          it keeps them. */}
      <div
        class={cn(
          portalVariants({ position: local.position }),
          local.overlay === false && "pointer-events-none",
        )}
      >
        {local.children}
      </div>
    </SheetPrimitive.Portal>
  )
}

const sheetVariants = cva(
  "fixed z-50 flex flex-col bg-background text-foreground shadow-xl outline-none data-[closed]:animate-out data-[closed]:fade-out-0 data-[closed]:duration-150 data-[expanded]:animate-in data-[expanded]:fade-in-0 data-[expanded]:duration-200",
  {
    variants: {
      position: {
        bottom:
          "inset-x-0 bottom-0 max-h-[85dvh] rounded-t-3xl border-t pb-[env(safe-area-inset-bottom)] data-[closed]:slide-out-to-bottom-4 data-[expanded]:slide-in-from-bottom-4",
        right:
          "inset-y-0 right-0 h-full w-full max-w-[420px] border-l data-[closed]:slide-out-to-right-4 data-[expanded]:slide-in-from-right-4",
      },
    },
    defaultVariants: { position: "right" },
  },
)

type SheetContentProps<T extends ValidComponent = "div"> = SheetPrimitive.DialogContentProps<T> &
  VariantProps<typeof sheetVariants> & {
    class?: string | undefined
    children?: JSX.Element
    /** Dims and blocks the page behind; off for a panel read alongside it. */
    overlay?: boolean
  }

const SheetContent = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SheetContentProps<T>>,
) => {
  const [local, others] = splitProps(props as SheetContentProps, [
    "position",
    "class",
    "children",
    "overlay",
  ])
  return (
    <SheetPortal position={local.position} overlay={local.overlay}>
      <Show when={local.overlay !== false}>
        <SheetPrimitive.Overlay class="fixed inset-0 z-50 bg-foreground/30 data-[closed]:animate-out data-[closed]:fade-out-0 data-[expanded]:animate-in data-[expanded]:fade-in-0" />
      </Show>
      <SheetPrimitive.Content
        class={cn(
          sheetVariants({ position: local.position }),
          local.overlay === false && "pointer-events-auto",
          local.class,
        )}
        {...others}
      >
        {local.children}
      </SheetPrimitive.Content>
    </SheetPortal>
  )
}

const SheetHeader: Component<ComponentProps<"div">> = (props) => {
  const [, rest] = splitProps(props, ["class"])
  return <div class={cn("flex items-center gap-3", props.class)} {...rest} />
}

type SheetTitleProps<T extends ValidComponent = "h2"> = SheetPrimitive.DialogTitleProps<T> & {
  class?: string | undefined
}

const SheetTitle = <T extends ValidComponent = "h2">(
  props: PolymorphicProps<T, SheetTitleProps<T>>,
) => {
  const [, rest] = splitProps(props as SheetTitleProps, ["class"])
  return (
    <SheetPrimitive.Title
      class={cn("font-display text-xl leading-tight tracking-[-0.02em]", props.class)}
      {...rest}
    />
  )
}

export { Sheet, SheetTrigger, SheetClose, SheetContent, SheetHeader, SheetTitle }
