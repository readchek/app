import { type JSX, splitProps } from "solid-js"
import { cn } from "../../lib/cn.ts"

export function Card(props: JSX.HTMLAttributes<HTMLDivElement>) {
  const [local, rest] = splitProps(props, ["class"])
  return (
    <div
      class={cn(
        "rounded-3xl border bg-card text-card-foreground shadow-[0_1px_2px_rgb(23_24_32/0.04),0_12px_40px_-12px_rgb(23_24_32/0.14)]",
        local.class,
      )}
      {...rest}
    />
  )
}

export function CardContent(props: JSX.HTMLAttributes<HTMLDivElement>) {
  const [local, rest] = splitProps(props, ["class"])
  return <div class={cn("p-5 sm:p-7", local.class)} {...rest} />
}

export function CardFooter(props: JSX.HTMLAttributes<HTMLDivElement>) {
  const [local, rest] = splitProps(props, ["class"])
  return (
    <div
      class={cn("border-t px-5 py-4 text-sm text-muted-foreground sm:px-7", local.class)}
      {...rest}
    />
  )
}
