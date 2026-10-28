import type { ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as SkeletonPrimitive from "@kobalte/core/skeleton"

import { cn } from "../../lib/cn.ts"

type SkeletonRootProps<T extends ValidComponent = "div"> =
  SkeletonPrimitive.SkeletonRootProps<T> & { class?: string | undefined }

/** A placeholder in the shape of content that's loading. */
const Skeleton = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SkeletonRootProps<T>>,
) => {
  const [local, others] = splitProps(props as SkeletonRootProps, ["class"])
  return (
    <SkeletonPrimitive.Root
      class={cn("rounded bg-muted data-[animate='true']:animate-pulse", local.class)}
      // Kobalte sizes a skeleton inline, full width and auto height, which
      // would beat the size classes every placeholder here is drawn with.
      style={{ width: undefined, height: undefined }}
      {...others}
    />
  )
}

export { Skeleton }
