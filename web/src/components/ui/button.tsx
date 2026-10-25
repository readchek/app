import { type JSX, splitProps } from "solid-js"
import { Button as ButtonPrimitive } from "@kobalte/core/button"
import { type VariantProps, cva } from "class-variance-authority"
import { cn } from "../../lib/cn.ts"

export const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-full font-semibold whitespace-nowrap transition-[background-color,color,box-shadow,transform] select-none focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:pointer-events-none disabled:opacity-50 active:scale-[0.98] [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground shadow-sm shadow-primary/25 hover:bg-primary/90",
        destructive:
          "bg-destructive text-destructive-foreground shadow-sm shadow-destructive/25 hover:bg-destructive/90",
        outline: "border border-input bg-card hover:bg-muted",
        ghost: "hover:bg-muted",
        link: "rounded-sm text-link underline-offset-4 hover:underline",
      },
      size: {
        default: "h-11 px-5 text-[15px]",
        lg: "h-13 px-6 text-base",
        sm: "h-9 px-3.5 text-sm",
        inline: "h-auto p-0 text-[length:inherit]",
      },
    },
    defaultVariants: { variant: "default", size: "default" },
  },
)

type ButtonProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof buttonVariants>

export function Button(props: ButtonProps) {
  const [local, rest] = splitProps(props, ["class", "variant", "size"])
  return (
    <ButtonPrimitive
      class={cn(buttonVariants({ variant: local.variant, size: local.size }), local.class)}
      {...rest}
    />
  )
}
