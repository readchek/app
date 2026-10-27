import { For, type JSX, Show, createMemo, createSignal } from "solid-js"
import type { TocItem } from "@readchek/reader"
import { Search } from "../../components/icons.tsx"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "../../components/ui/dialog.tsx"
import { Input } from "../../components/ui/input.tsx"
import { cn } from "../../lib/cn.ts"

/** Folds case and accents, so "etude" finds "Étude". */
function folded(text: string): string {
  return text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
}

/** An entry found by the filter, with the entries it's inside, such as a part of the book. */
type Entry = { item: TocItem; within: string; words: string[]; text: string }

/** Every entry, nested ones after their parent, for filtering. */
function flattened(items: TocItem[], parents: string[] = []): Entry[] {
  return items.flatMap((item) => {
    const text = folded([...parents, item.title].join(" "))
    const entry = { item, within: parents.join(" › "), words: text.split(/[^\p{L}\p{N}]+/u), text }
    return [entry, ...flattened(item.children, [...parents, item.title])]
  })
}

const numerals: [number, string][] = [
  [1000, "m"],
  [900, "cm"],
  [500, "d"],
  [400, "cd"],
  [100, "c"],
  [90, "xc"],
  [50, "l"],
  [40, "xl"],
  [10, "x"],
  [9, "ix"],
  [5, "v"],
  [4, "iv"],
  [1, "i"],
]

/** A number in Roman numerals, as older books number their chapters. */
function roman(number: number): string {
  let rest = number
  return numerals.reduce((text, [value, numeral]) => {
    const count = Math.floor(rest / value)
    rest -= count * value
    return text + numeral.repeat(count)
  }, "")
}

/** Whether an entry has every word typed, so "12" also finds "XII". */
function matches(entry: Entry, words: string[]): boolean {
  return words.every((word) => {
    if (entry.text.includes(word)) return true
    const number = /^\d+$/.test(word) ? Number(word) : 0
    return number > 0 && number < 4000 && entry.words.includes(roman(number))
  })
}

/** A book's or PDF's contents, with a filter for finding a chapter by name. */
export function ContentsDialog(props: {
  open: boolean
  onOpenChange: (open: boolean) => void
  items: TocItem[]
  current: TocItem | undefined
  choose: (item: TocItem) => void
}) {
  const [filter, setFilter] = createSignal("")
  const all = createMemo(() => flattened(props.items))
  const found = createMemo(() => {
    const words = folded(filter()).split(/\s+/).filter(Boolean)
    return words.length === 0 ? undefined : all().filter((entry) => matches(entry, words))
  })
  const choose = (item: TocItem) => {
    setFilter("")
    props.choose(item)
  }

  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) setFilter("")
        props.onOpenChange(open)
      }}
    >
      <DialogContent class="max-w-xl">
        <DialogHeader>
          <DialogTitle>Contents</DialogTitle>
        </DialogHeader>
        {/* Short contents don't need finding in. */}
        <Show when={all().length > 8}>
          <form
            class="sticky -top-6 z-10 -my-2 bg-card py-2 sm:-top-8"
            onSubmit={(event) => {
              event.preventDefault()
              const first = found()?.[0]
              if (first) choose(first.item)
            }}
          >
            <label class="relative block [&>svg]:absolute [&>svg]:top-1/2 [&>svg]:left-3.5 [&>svg]:size-[18px] [&>svg]:-translate-y-1/2 [&>svg]:text-muted-foreground">
              <Search />
              <span class="sr-only">Find a chapter</span>
              <Input
                type="search"
                class="ps-10"
                placeholder="Find a chapter"
                enterkeyhint="go"
                value={filter()}
                onInput={(event) => setFilter(event.currentTarget.value)}
              />
            </label>
          </form>
        </Show>
        <nav aria-label="Contents" class="-mx-2">
          <Show
            when={found()}
            fallback={
              <TocList items={props.items} current={props.current} depth={0} choose={choose} />
            }
          >
            {(entries) => (
              <Show
                when={entries().length > 0}
                fallback={
                  <p class="px-2 py-2.5 text-[15px] text-muted-foreground">
                    No chapter matches “{filter().trim()}”.
                  </p>
                }
              >
                <ul>
                  <For each={entries()}>
                    {(entry) => (
                      <li>
                        <TocButton
                          item={entry.item}
                          current={props.current}
                          detail={entry.within}
                          choose={choose}
                        />
                      </li>
                    )}
                  </For>
                </ul>
              </Show>
            )}
          </Show>
        </nav>
      </DialogContent>
    </Dialog>
  )
}

/** A table of contents, nested as the book nests it. */
function TocList(props: {
  items: TocItem[]
  current: TocItem | undefined
  depth: number
  choose: (item: TocItem) => void
}): JSX.Element {
  return (
    <ul class={cn(props.depth > 0 && "ms-4")}>
      <For each={props.items}>
        {(item) => (
          <li>
            <TocButton item={item} current={props.current} choose={props.choose} />
            <Show when={item.children.length > 0}>
              <TocList
                items={item.children}
                current={props.current}
                depth={props.depth + 1}
                choose={props.choose}
              />
            </Show>
          </li>
        )}
      </For>
    </ul>
  )
}

/** One entry, with what it's inside when it's shown apart from it. */
function TocButton(props: {
  item: TocItem
  current: TocItem | undefined
  detail?: string
  choose: (item: TocItem) => void
}) {
  return (
    <button
      type="button"
      class={cn(
        "w-full rounded-lg px-2 py-2.5 text-start text-[15px] transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/40 focus-visible:outline-none",
        props.current === props.item && "font-semibold text-link",
      )}
      aria-current={props.current === props.item ? "location" : undefined}
      onClick={() => props.choose(props.item)}
    >
      {props.item.title}
      <Show when={props.detail}>
        <span class="block text-[13px] font-normal text-muted-foreground">{props.detail}</span>
      </Show>
    </button>
  )
}
