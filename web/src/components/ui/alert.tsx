import { type JSX, splitProps } from "solid-js"
import { Alert as AlertPrimitive } from "@kobalte/core/alert"
import { type VariantProps, cva } from "class-variance-authority"
import { cn } from "../../lib/cn.ts"

const alertVariants = cva(
  "flex items-start gap-3 rounded-2xl border px-4 py-3.5 text-[15px] leading-snug [&>svg]:mt-0.5 [&>svg]:size-[18px] [&>svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-muted/60",
        note: "border-transparent bg-butter text-butter-foreground",
        success: "border-success/25 bg-success/8 [&>svg]:text-success",
        destructive: "border-destructive/30 bg-destructive/8 [&>svg]:text-destructive",
      },
    },
    defaultVariants: { variant: "default" },
  },
)

type AlertProps = JSX.HTMLAttributes<HTMLDivElement> &
  VariantProps<typeof alertVariants> & { role?: "alert" | "status" | "note" }

/** A message beside the content. Kobalte gives it `role="alert"`; pass `role="status"` for news that isn't urgent. */
export function Alert(props: AlertProps) {
  const [local, rest] = splitProps(props, ["class", "variant"])
  return (
    <AlertPrimitive class={cn(alertVariants({ variant: local.variant }), local.class)} {...rest} />
  )
}
