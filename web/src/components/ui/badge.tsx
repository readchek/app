import { type JSX, splitProps } from "solid-js"
import { type VariantProps, cva } from "class-variance-authority"
import { cn } from "../../lib/cn.ts"

const badgeVariants = cva(
  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold leading-4",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground",
        secondary: "bg-muted text-muted-foreground",
        butter: "bg-butter text-butter-foreground",
      },
    },
    defaultVariants: { variant: "default" },
  },
)

export function Badge(
  props: JSX.HTMLAttributes<HTMLSpanElement> & VariantProps<typeof badgeVariants>,
) {
  const [local, rest] = splitProps(props, ["class", "variant"])
  return <span class={cn(badgeVariants({ variant: local.variant }), local.class)} {...rest} />
}
