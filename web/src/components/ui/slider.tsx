import type { JSX, ValidComponent } from "solid-js"
import { splitProps } from "solid-js"

import type { PolymorphicProps } from "@kobalte/core/polymorphic"
import * as SliderPrimitive from "@kobalte/core/slider"

import { cn } from "../../lib/cn.ts"
import { Label } from "./label.tsx"

// solid-ui's slider in Chek's shape: a thin track in brand blue.

type SliderRootProps<T extends ValidComponent = "div"> = SliderPrimitive.SliderRootProps<T> & {
  class?: string | undefined
}

// Exported as SliderRoot until the reader moves off the Slider wrapper
// below; then it takes solid-ui's name.
const SliderRoot = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SliderRootProps<T>>,
) => {
  const [local, others] = splitProps(props as SliderRootProps, ["class"])
  return (
    <SliderPrimitive.Root
      class={cn("relative flex w-full touch-none flex-col items-center select-none", local.class)}
      {...others}
    />
  )
}

type SliderTrackProps<T extends ValidComponent = "div"> = SliderPrimitive.SliderTrackProps<T> & {
  class?: string | undefined
}

const SliderTrack = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SliderTrackProps<T>>,
) => {
  const [local, others] = splitProps(props as SliderTrackProps, ["class"])
  return (
    <SliderPrimitive.Track
      class={cn("relative h-1.5 w-full grow rounded-full bg-foreground/15", local.class)}
      {...others}
    />
  )
}

type SliderFillProps<T extends ValidComponent = "div"> = SliderPrimitive.SliderFillProps<T> & {
  class?: string | undefined
}

const SliderFill = <T extends ValidComponent = "div">(
  props: PolymorphicProps<T, SliderFillProps<T>>,
) => {
  const [local, others] = splitProps(props as SliderFillProps, ["class"])
  return (
    <SliderPrimitive.Fill
      class={cn("absolute h-full rounded-full bg-link", local.class)}
      {...others}
    />
  )
}

type SliderThumbProps<T extends ValidComponent = "span"> = SliderPrimitive.SliderThumbProps<T> & {
  class?: string | undefined
  children?: JSX.Element
}

const SliderThumb = <T extends ValidComponent = "span">(
  props: PolymorphicProps<T, SliderThumbProps<T>>,
) => {
  const [local, others] = splitProps(props as SliderThumbProps, ["class", "children"])
  return (
    <SliderPrimitive.Thumb
      class={cn(
        "-top-[7px] block size-5 rounded-full border-2 border-link bg-background shadow-sm transition-shadow focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none disabled:pointer-events-none disabled:opacity-50",
        local.class,
      )}
      {...others}
    >
      <SliderPrimitive.Input />
    </SliderPrimitive.Thumb>
  )
}

const SliderLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, SliderPrimitive.SliderLabelProps<T>>,
) => {
  return <SliderPrimitive.Label as={Label} {...props} />
}

const SliderValueLabel = <T extends ValidComponent = "label">(
  props: PolymorphicProps<T, SliderPrimitive.SliderValueLabelProps<T>>,
) => {
  return <SliderPrimitive.ValueLabel as={Label} {...props} />
}

/** One value along a track, such as a page in a book. The reader's controls still use this. */
function Slider(props: {
  class?: string
  label: string
  value: number
  minValue: number
  maxValue: number
  onChange: (value: number) => void
  onChangeEnd?: (value: number) => void
  getValueLabel?: (value: number) => string
  disabled?: boolean
  /** Fills from the end, as a right-to-left comic's scrubber does. */
  inverted?: boolean
}) {
  return (
    <SliderRoot
      class={cn("flex-row", props.class)}
      value={[props.value]}
      minValue={props.minValue}
      maxValue={props.maxValue}
      onChange={(values: number[]) => props.onChange(values[0]!)}
      onChangeEnd={(values: number[]) => props.onChangeEnd?.(values[0]!)}
      getValueLabel={
        props.getValueLabel
          ? (params: { values: number[] }) => props.getValueLabel!(params.values[0]!)
          : undefined
      }
      disabled={props.disabled}
      inverted={props.inverted}
    >
      <SliderLabel class="sr-only">{props.label}</SliderLabel>
      <SliderTrack>
        <SliderFill />
        <SliderThumb />
      </SliderTrack>
    </SliderRoot>
  )
}

export { Slider, SliderRoot, SliderTrack, SliderFill, SliderThumb, SliderLabel, SliderValueLabel }
