import type { Component, ComponentProps } from "solid-js"
import { splitProps } from "solid-js"

import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

import { cn } from "../../lib/cn.ts"

// solid-ui's badge, as a span so it can sit inside a line of text, with
// Chek's butter for demo and preview labels.

const badgeVariants = cva(
  "inline-flex items-center rounded-full border border-transparent px-2 py-0.5 text-xs leading-4 font-semibold",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground",
        secondary: "bg-secondary text-muted-foreground",
        butter: "bg-butter text-butter-foreground",
        success: "bg-success/12 text-success",
        destructive: "bg-destructive/12 text-destructive",
        outline: "border-input text-muted-foreground",
      },
    },
    defaultVariants: { variant: "default" },
  },
)

type BadgeProps = ComponentProps<"span"> & VariantProps<typeof badgeVariants>

const Badge: Component<BadgeProps> = (props) => {
  const [local, others] = splitProps(props, ["class", "variant"])
  return <span class={cn(badgeVariants({ variant: local.variant }), local.class)} {...others} />
}

export type { BadgeProps }
export { Badge, badgeVariants }
