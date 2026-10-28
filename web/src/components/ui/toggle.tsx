import type { ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as ToggleButtonPrimitive from "@kobalte/core/toggle-button"
import { cva } from "class-variance-authority"
import type { VariantProps } from "class-variance-authority"

import { cn } from "../../lib/cn.ts"

// solid-ui's toggle. The segmented variant is Chek's: a pressed segment
// lifts out of the muted track its group draws.

const toggleVariants = cva(
  "inline-flex items-center justify-center rounded-lg text-sm font-semibold transition-colors focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default:
          "bg-transparent hover:bg-muted data-[pressed]:bg-accent data-[pressed]:text-accent-foreground",
        outline:
          "border border-input bg-transparent hover:bg-muted data-[pressed]:bg-accent data-[pressed]:text-accent-foreground",
        segmented:
          "text-muted-foreground hover:text-foreground data-[pressed]:bg-card data-[pressed]:text-foreground data-[pressed]:shadow-sm",
      },
      size: {
        default: "h-9 px-3",
        sm: "h-8 px-2",
        lg: "h-10 px-3",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)

type ToggleButtonRootProps<T extends ValidComponent = "button"> =
  ToggleButtonPrimitive.ToggleButtonRootProps<T> &
    VariantProps<typeof toggleVariants> & { class?: string | undefined }

const Toggle = <T extends ValidComponent = "button">(
  props: PolymorphicProps<T, ToggleButtonRootProps<T>>,
) => {
  const [local, others] = splitProps(props as ToggleButtonRootProps, ["class", "variant", "size"])
  return (
    <ToggleButtonPrimitive.Root
      class={cn(toggleVariants({ variant: local.variant, size: local.size }), local.class)}
      {...others}
    />
  )
}

export type { ToggleButtonRootProps as ToggleProps }
export { toggleVariants, Toggle }
