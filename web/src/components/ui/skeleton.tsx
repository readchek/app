import { type JSX, splitProps } from "solid-js"
import { cn } from "../../lib/cn.ts"

/** A placeholder in the shape of content that's loading. After solid-ui's skeleton. */
export function Skeleton(props: JSX.HTMLAttributes<HTMLDivElement>) {
  const [local, rest] = splitProps(props, ["class"])
  return <div class={cn("animate-pulse rounded bg-muted", local.class)} {...rest} />
}
