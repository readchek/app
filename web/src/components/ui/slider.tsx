import { Slider as SliderPrimitive } from "@kobalte/core/slider"
import { cn } from "../../lib/cn.ts"

/** One value along a track, such as a page in a book. After solid-ui's slider. */
export function Slider(props: {
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
    <SliderPrimitive
      class={cn("relative flex w-full touch-none items-center select-none", props.class)}
      value={[props.value]}
      minValue={props.minValue}
      maxValue={props.maxValue}
      onChange={(values) => props.onChange(values[0]!)}
      onChangeEnd={(values) => props.onChangeEnd?.(values[0]!)}
      getValueLabel={
        props.getValueLabel ? (params) => props.getValueLabel!(params.values[0]!) : undefined
      }
      disabled={props.disabled}
      inverted={props.inverted}
    >
      <SliderPrimitive.Label class="sr-only">{props.label}</SliderPrimitive.Label>
      <SliderPrimitive.Track class="relative h-1.5 w-full grow rounded-full bg-foreground/15">
        <SliderPrimitive.Fill class="absolute h-full rounded-full bg-link" />
        <SliderPrimitive.Thumb class="-top-[7px] block size-5 rounded-full border-2 border-link bg-background shadow-sm transition-shadow focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none">
          <SliderPrimitive.Input />
        </SliderPrimitive.Thumb>
      </SliderPrimitive.Track>
    </SliderPrimitive>
  )
}
