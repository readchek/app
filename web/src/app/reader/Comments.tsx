import {
  type Accessor,
  For,
  type JSX,
  Match,
  Show,
  Switch,
  batch,
  createEffect,
  createSignal,
  on,
  onCleanup,
} from "solid-js"
import { createResource } from "../../lib/resource.ts"
import { cn } from "../../lib/cn.ts"
import { ArrowUpRight, Bubble, Close, Ellipsis } from "../../components/icons.tsx"
import { Button, buttonVariants } from "../../components/ui/button.tsx"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../../components/ui/dropdown-menu.tsx"
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "../../components/ui/sheet.tsx"
import { Skeleton } from "../../components/ui/skeleton.tsx"
import { ToggleGroup, ToggleGroupItem } from "../../components/ui/toggle-group.tsx"
import type { Account } from "../accounts.ts"
import { loadImage } from "../images.ts"
import {
  type Comment,
  type CommentOrder,
  type CommentRun,
  chapterComments,
  commentReplies,
  commentSummary,
} from "../sites/api.ts"
import {
  Switch as Toggle,
  SwitchControl as ToggleControl,
  SwitchDescription as ToggleDescription,
  SwitchLabel as ToggleLabel,
  SwitchThumb as ToggleThumb,
} from "../../components/ui/switch.tsx"
import { commentSettings, hideCommenter, isHiddenCommenter, showComments } from "./settings.ts"

/**
 * A link a site gave us, if it is a plain https address. Comments and their
 * links come from third-party sites, so anything else, such as a
 * `javascript:` URL, is dropped rather than put in an `href`. The iOS
 * reader applies the same rule.
 */
function safeLink(text: string | null | undefined): string | undefined {
  if (!text) return undefined
  try {
    const url = new URL(text)
    return url.protocol === "https:" && url.hostname ? url.href : undefined
  } catch {
    return undefined
  }
}

// Readers' comments on a chapter, as the source's site shows them. They're
// read-only: Chek passes them on and never posts. They open from the top
// bar or the end of the chapter into a panel along the side, or the bottom
// on a phone, and closing it leaves the reader where it was.

/** Where a chapter's comments come from. */
export type CommentSource = {
  account: Account
  extensionId: string
  chapterId: string
  /** The source's name, as its extension gives it, such as `Comix`. */
  site: string
  /** The orders it lists comments in, its default first; empty for a count only. */
  orders: CommentOrder[]
}

export type Comments = {
  source: CommentSource
  /** How many comments there are, once known, and where; null for none. */
  summary: Accessor<{ count: number; url: string | null } | null | undefined>
  open: Accessor<boolean>
  setOpen: (open: boolean) => void
}

export function createComments(source: CommentSource): Comments {
  const [open, setOpen] = createSignal(false)
  const [summary] = createResource(
    () => commentSettings().show || undefined,
    async () => {
      try {
        const found = await commentSummary(source.account, source.extensionId, source.chapterId)
        return found && found.count > 0 ? found : null
      } catch {
        // A count is only a way in; without one there's nothing to show.
        return null
      }
    },
  )
  return {
    source,
    summary: () => (commentSettings().show ? summary() : null),
    open,
    setOpen,
  }
}

const countLabel = (count: number) => `${count} ${count === 1 ? "comment" : "comments"}`

/**
 * Opens the panel, or the thread on the site for a source that gives only
 * a count. Shows nothing while there are no comments.
 */
function Entry(props: {
  comments: Comments
  class: string
  variant: "ghost" | "link"
  children: (count: number) => JSX.Element
}) {
  return (
    <Show when={props.comments.summary()}>
      {(summary) => (
        <Show
          when={props.comments.source.orders.length > 0}
          fallback={
            <Show when={safeLink(summary().url)}>
              {(url) => (
                <a
                  href={url()}
                  target="_blank"
                  rel="noopener noreferrer nofollow"
                  class={cn(buttonVariants({ variant: props.variant, size: "sm" }), props.class)}
                  aria-label={`${countLabel(summary().count)} on ${props.comments.source.site}`}
                >
                  {props.children(summary().count)}
                </a>
              )}
            </Show>
          }
        >
          <Button
            variant={props.variant}
            size="sm"
            class={props.class}
            aria-label={countLabel(summary().count)}
            onClick={() => props.comments.setOpen(true)}
          >
            {props.children(summary().count)}
          </Button>
        </Show>
      )}
    </Show>
  )
}

/** The comments button in the reader's top bar. */
export function CommentsButton(props: { comments: Comments }) {
  return (
    <Entry comments={props.comments} variant="ghost" class="h-10 gap-1.5 px-2.5 [&_svg]:size-5">
      {(count) => (
        <>
          <Bubble />
          <span class="text-[13px] tabular-nums">{count}</span>
        </>
      )}
    </Entry>
  )
}

/** The comments line under what's up next, at the end of the chapter. */
export function CommentsLink(props: { comments: Comments }) {
  return (
    <Entry
      comments={props.comments}
      variant="link"
      class="mt-1 h-auto gap-1.5 px-0 py-0 text-[13px] font-semibold [&_svg]:size-3.5"
    >
      {(count) => (
        <>
          <Bubble />
          {countLabel(count)}
        </>
      )}
    </Entry>
  )
}

const wideQuery = matchMedia("(min-width: 640px)")
const [wide, setWide] = createSignal(wideQuery.matches)
wideQuery.addEventListener("change", () => setWide(wideQuery.matches))

/** The width the panel takes beside the page on a wide window. */
export const PANEL_WIDTH = 420

/**
 * Whether the panel is open beside the page, which the reader makes room
 * for so the page stays whole and readable next to it.
 */
export const isDocked = (comments: Comments | undefined) =>
  comments !== undefined && comments.open() && wide()

/**
 * The panel of comments, along the trailing side or, on a phone, the
 * bottom. It's read alongside the page, never over it: nothing dims, and
 * the page keeps turning with taps, swipes and keys while it's open.
 */
export function CommentsPanel(props: { comments: Comments }) {
  const source = () => props.comments.source
  const side = () => (wide() ? "right" : "bottom")

  const [order, setOrder] = createSignal<CommentOrder | undefined>(source().orders[0])
  const [items, setItems] = createSignal<Comment[]>([])
  const [next, setNext] = createSignal<string | null>(null)
  const [phase, setPhase] = createSignal<"loading" | "ready" | "more" | "failed">("loading")
  // Answers to a load that's been overtaken, by another order or a close, are dropped.
  let load = 0

  const fetchPage = async (cursor?: string) => {
    const ticket = ++load
    setPhase(cursor ? "more" : "loading")
    try {
      const page = await chapterComments(source().account, source().extensionId, {
        chapterId: source().chapterId,
        order: order(),
        cursor,
      })
      if (ticket !== load) return
      batch(() => {
        setItems((current) => (cursor ? [...current, ...page.items] : page.items))
        setNext(page.next)
        setPhase("ready")
      })
    } catch {
      if (ticket === load) setPhase(cursor ? "ready" : "failed")
    }
  }

  createEffect(
    on([props.comments.open, order], ([open]) => {
      if (!open) {
        load++
        return
      }
      setItems([])
      setNext(null)
      void fetchPage()
    }),
  )

  let scroller: HTMLDivElement | undefined
  const sentinel = (node: HTMLDivElement) => {
    const watcher = new IntersectionObserver(
      ([entry]) => {
        const cursor = next()
        if (entry?.isIntersecting && cursor && phase() === "ready") void fetchPage(cursor)
      },
      { root: scroller, rootMargin: "400px" },
    )
    watcher.observe(node)
    onCleanup(() => watcher.disconnect())
  }

  const count = () => props.comments.summary()?.count

  return (
    <Sheet
      open={props.comments.open()}
      onOpenChange={props.comments.setOpen}
      modal={false}
      preventScroll={false}
    >
      <SheetContent
        position={side()}
        overlay={false}
        aria-describedby={undefined}
        class="max-sm:max-h-[60dvh]"
        // Reading on doesn't close it; only its close button and Escape do.
        onInteractOutside={(event) => event.preventDefault()}
        // The page keeps the keyboard: opening the panel doesn't take it.
        onOpenAutoFocus={(event) => event.preventDefault()}
        // Escape closes only the panel. Marking it handled keeps the reader
        // from also taking it as "leave the chapter".
        onEscapeKeyDown={(event) => {
          event.preventDefault()
          props.comments.setOpen(false)
        }}
      >
        <Show when={side() === "bottom"}>
          <div class="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-border" aria-hidden="true" />
        </Show>
        <SheetHeader class="border-b px-5 pt-3 pb-3 sm:pt-4">
          <SheetTitle>Comments</SheetTitle>
          <Show when={count()}>
            {(total) => <span class="text-sm text-muted-foreground tabular-nums">{total()}</span>}
          </Show>
          <div class="ml-auto flex items-center gap-1">
            <Show when={source().orders.length > 1}>
              <ToggleGroup
                variant="segmented"
                aria-label="Order"
                value={order()}
                onChange={(value: string | null) => value && setOrder(value as CommentOrder)}
              >
                <For each={source().orders}>
                  {(one) => (
                    <ToggleGroupItem value={one} class="px-2.5 text-[13px]">
                      {orderLabel[one]}
                    </ToggleGroupItem>
                  )}
                </For>
              </ToggleGroup>
            </Show>
            <SheetClose
              class={cn(
                buttonVariants({ variant: "ghost", size: "sm" }),
                "size-9 px-0 [&_svg]:size-5",
              )}
              aria-label="Close"
            >
              <Close />
            </SheetClose>
          </div>
        </SheetHeader>

        <div ref={(node) => (scroller = node)} class="min-h-0 flex-1 overflow-y-auto">
          <Switch>
            <Match when={phase() === "loading"}>
              <div class="grid gap-6 px-5 py-5" role="status" aria-label="Loading comments">
                <For each={[0.95, 0.7, 0.85, 0.6]}>
                  {(width) => (
                    <div class="grid gap-2">
                      <Skeleton class="h-3.5 w-2/5" />
                      <Skeleton class="h-3.5" style={{ width: `${width * 100}%` }} />
                      <Skeleton class="h-3.5 w-3/5" />
                    </div>
                  )}
                </For>
              </div>
            </Match>
            <Match when={phase() === "failed"}>
              <div class="grid justify-items-center gap-2 px-8 pt-24 text-center text-sm text-muted-foreground">
                <p>Couldn't load comments from {source().site}.</p>
                <Button
                  variant="link"
                  size="sm"
                  class="h-auto px-0"
                  onClick={() => void fetchPage()}
                >
                  Try again
                </Button>
              </div>
            </Match>
            <Match when={items().length === 0}>
              <p class="px-8 pt-24 text-center text-sm text-muted-foreground">No comments yet.</p>
            </Match>
            <Match when={true}>
              <ul>
                <For each={items()}>
                  {(comment) => (
                    <li class="border-b">
                      <Thread comment={comment} source={source()} />
                    </li>
                  )}
                </For>
              </ul>
              <Show when={next()}>
                <div ref={sentinel} class="flex justify-center py-5">
                  <Show when={phase() === "more"}>
                    <Skeleton class="h-3 w-24" />
                  </Show>
                </div>
              </Show>
            </Match>
          </Switch>
        </div>

        <Show
          when={
            phase() !== "loading" && phase() !== "failed" && safeLink(props.comments.summary()?.url)
          }
        >
          {(url) => (
            <footer class="flex items-center justify-between gap-4 border-t px-5 pt-3 pb-4 text-[13px] text-muted-foreground">
              <span>From {source().site} · read-only</span>
              <a
                href={url()}
                target="_blank"
                rel="noopener noreferrer nofollow"
                class="inline-flex items-center gap-1 font-semibold text-link [&_svg]:size-3.5"
              >
                Open thread
                <ArrowUpRight />
              </a>
            </footer>
          )}
        </Show>
      </SheetContent>
    </Sheet>
  )
}

const orderLabel: Record<CommentOrder, string> = {
  top: "Top",
  newest: "Newest",
  oldest: "Oldest",
}

/** A top-level comment and, once asked for, its replies. */
function Thread(props: { comment: Comment; source: CommentSource }) {
  const [shown, setShown] = createSignal(false)
  const [replies] = createResource(
    () => shown() || undefined,
    () =>
      commentReplies(props.source.account, props.source.extensionId, {
        chapterId: props.source.chapterId,
        commentId: props.comment.id,
      }),
  )
  const toggle = () =>
    props.comment.replyCount > 0 ? (
      <Button
        variant="link"
        size="sm"
        class="h-auto px-0 text-[13px] font-semibold"
        aria-expanded={shown()}
        onClick={() => setShown(!shown())}
      >
        {shown()
          ? "Hide replies"
          : `${props.comment.replyCount} ${props.comment.replyCount === 1 ? "reply" : "replies"}`}
      </Button>
    ) : undefined
  return (
    <div class="px-5 py-3.5">
      <Row comment={props.comment} source={props.source} extra={toggle()} />
      <Show when={shown()}>
        <div class="mt-2.5 border-l-2 pl-3.5">
          <Switch>
            <Match when={replies.error}>
              <p class="py-2 text-[13px] text-muted-foreground">Couldn't load the replies.</p>
            </Match>
            <Match when={replies()}>
              {(page) => (
                <ul class="grid gap-3 py-1">
                  <For each={page().items}>
                    {(reply) => (
                      <li>
                        <Row comment={reply} source={props.source} />
                      </li>
                    )}
                  </For>
                </ul>
              )}
            </Match>
            <Match when={true}>
              <Skeleton class="my-2 h-3.5 w-3/5" />
            </Match>
          </Switch>
        </div>
      </Show>
    </div>
  )
}

/** One comment, or a line saying its author is hidden. */
function Row(props: { comment: Comment; source: CommentSource; extra?: JSX.Element }) {
  const name = () => props.comment.author.name
  const hidden = () => isHiddenCommenter(props.source.extensionId, name())
  return (
    <Show
      when={!hidden()}
      fallback={
        <div class="flex flex-wrap items-center gap-x-1 text-[13px] text-muted-foreground">
          <span>Comments from {name()} hidden ·</span>
          <Button
            variant="link"
            size="sm"
            class="h-auto px-0 text-[13px] font-semibold"
            onClick={() => hideCommenter(props.source.extensionId, name(), false)}
          >
            Show
          </Button>
          <Show when={props.extra}>
            <span class="basis-full">{props.extra}</span>
          </Show>
        </div>
      }
    >
      <article class="relative" aria-label={`Comment by ${name()}`}>
        <header class="flex items-baseline gap-1.5 pr-9 text-[13px] text-muted-foreground">
          <span class="text-[14px] font-semibold text-foreground">{name()}</span>
          <Show when={props.comment.author.badge}>{(badge) => <span>· {badge()}</span>}</Show>
          <Show when={props.comment.published}>
            {(published) => (
              <time datetime={published()} title={new Date(published()).toLocaleString()}>
                {ago(published())}
              </time>
            )}
          </Show>
          <Show when={props.comment.edited}>
            <span>· edited</span>
          </Show>
        </header>
        <CommentMenu comment={props.comment} source={props.source} />
        <Body comment={props.comment} />
        <Show when={props.comment.images.length > 0}>
          <div class="mt-2 flex flex-wrap gap-2">
            <For each={props.comment.images}>
              {(image) => <CommentImage account={props.source.account} path={image} />}
            </For>
          </div>
        </Show>
        <div class="mt-1.5 flex items-center gap-4 text-[13px] text-muted-foreground">
          <Show when={props.comment.score !== null}>
            <span aria-label={`${props.comment.score} upvotes`}>▲ {props.comment.score}</span>
          </Show>
          {props.extra}
        </div>
      </article>
    </Show>
  )
}

/** The comment's text, with its spoilers covered until asked for. */
function Body(props: { comment: Comment }) {
  const [revealed, setRevealed] = createSignal(false)
  const reveal = () => setRevealed(true)
  return (
    <Show
      when={!props.comment.spoiler || revealed()}
      fallback={
        <button
          type="button"
          class="mt-1.5 flex h-10 w-full items-center rounded-lg bg-muted px-3 text-[13px] font-semibold text-muted-foreground"
          onClick={reveal}
        >
          Spoiler · Show
        </button>
      }
    >
      <p class="mt-1 text-[15px] leading-[1.45] break-words whitespace-pre-line">
        <Show when={props.comment.replyTo}>
          {(to) => <span class="text-muted-foreground">@{to()} </span>}
        </Show>
        <For each={props.comment.body}>
          {(run) => <RunText run={run} revealed={revealed()} reveal={reveal} />}
        </For>
      </p>
    </Show>
  )
}

function RunText(props: { run: CommentRun; revealed: boolean; reveal: () => void }) {
  const styled = () => (
    <span
      class={cn(
        props.run.bold && "font-semibold",
        props.run.italic && "italic",
        props.run.strike && "line-through",
        props.run.code && "rounded bg-muted px-1 font-mono text-[13px]",
        props.run.quote && "text-muted-foreground italic",
      )}
    >
      {props.run.text}
    </span>
  )
  return (
    <Switch fallback={styled()}>
      <Match when={props.run.spoiler && !props.revealed}>
        {/* The text isn't in the page until revealed, so a screen reader can't speak it. */}
        <button
          type="button"
          class="mx-0.5 inline-flex h-[22px] items-center rounded-[5px] bg-muted px-2 align-[1px] text-[12px] font-semibold text-muted-foreground"
          onClick={props.reveal}
        >
          Spoiler
        </button>
      </Match>
      <Match when={safeLink(props.run.link)}>
        {(link) => (
          <a
            href={link()}
            target="_blank"
            rel="noopener noreferrer nofollow"
            class="text-link underline underline-offset-2"
          >
            {styled()}
          </a>
        )}
      </Match>
    </Switch>
  )
}

/** Hide the author, or report or open the comment on its site. */
function CommentMenu(props: { comment: Comment; source: CommentSource }) {
  const visit = (url: string) => window.open(url, "_blank", "noopener,noreferrer")
  return (
    <DropdownMenu placement="bottom-end">
      <DropdownMenuTrigger
        class={cn(
          buttonVariants({ variant: "ghost", size: "sm" }),
          "absolute -top-1.5 -right-2 size-8 px-0 text-muted-foreground [&_svg]:size-[18px]",
        )}
        aria-label={`More for the comment by ${props.comment.author.name}`}
      >
        <Ellipsis />
      </DropdownMenuTrigger>
      {/* Keys stay in the menu rather than reaching the reader, which would turn the page. */}
      <DropdownMenuContent onKeyDown={(event: KeyboardEvent) => event.stopPropagation()}>
        <DropdownMenuItem
          onSelect={() => hideCommenter(props.source.extensionId, props.comment.author.name, true)}
        >
          Hide comments from {props.comment.author.name}
        </DropdownMenuItem>
        <Show when={safeLink(props.comment.url)}>
          {(url) => (
            <>
              <DropdownMenuItem onSelect={() => visit(url())}>
                Report on {props.source.site}
                <span class="text-muted-foreground [&_svg]:size-3.5">
                  <ArrowUpRight />
                </span>
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => visit(url())}>
                Open on {props.source.site}
                <span class="text-muted-foreground [&_svg]:size-3.5">
                  <ArrowUpRight />
                </span>
              </DropdownMenuItem>
            </>
          )}
        </Show>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

/** A picture attached to a comment, fetched through the server like a page. */
function CommentImage(props: { account: Account; path: string }) {
  const [url] = createResource(
    () => props.path,
    async (path) => URL.createObjectURL(await loadImage(props.account, path)),
  )
  createEffect(() => {
    const made = url.state === "ready" ? url() : undefined
    if (made) onCleanup(() => URL.revokeObjectURL(made))
  })
  return (
    <Show when={url.state === "ready" && url()}>
      {(src) => (
        <img src={src()} alt="" class="max-h-48 max-w-[60%] rounded-lg border object-contain" />
      )}
    </Show>
  )
}

/** How long ago, as comment threads put it: now, 5m, 2h, 3d, then the date. */
function ago(iso: string): string {
  const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60_000)
  if (!Number.isFinite(minutes)) return ""
  if (minutes < 1) return "now"
  if (minutes < 60) return `${minutes}m`
  if (minutes < 60 * 24) return `${Math.round(minutes / 60)}h`
  if (minutes < 60 * 24 * 7) return `${Math.round(minutes / (60 * 24))}d`
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  })
}

/** Whether comments show, and whose are hidden, for the reading settings. */
export function CommentSettings(props: { source: CommentSource }) {
  const hidden = () => commentSettings().hidden[props.source.extensionId] ?? []
  return (
    <div class="grid gap-3">
      <Toggle
        class="flex cursor-pointer items-start justify-between gap-4"
        checked={commentSettings().show}
        onChange={(on) => showComments(on)}
      >
        <span class="grid min-w-0 gap-0.5">
          <ToggleLabel class="text-sm font-semibold">Show comments</ToggleLabel>
          <ToggleDescription class="text-[13px] text-muted-foreground">
            From {props.source.site}, read-only.
          </ToggleDescription>
        </span>
        <ToggleControl class="mt-0.5">
          <ToggleThumb />
        </ToggleControl>
      </Toggle>
      <Show when={hidden().length > 0}>
        <div class="grid gap-1.5">
          <span class="text-sm font-semibold">Hidden commenters</span>
          <ul class="grid gap-1">
            <For each={hidden()}>
              {(name) => (
                <li class="flex items-center justify-between gap-3 text-[13px]">
                  <span class="min-w-0 truncate">{name}</span>
                  <Button
                    variant="link"
                    size="sm"
                    class="h-auto px-0 text-[13px] font-semibold"
                    onClick={() => hideCommenter(props.source.extensionId, name, false)}
                  >
                    Show
                  </Button>
                </li>
              )}
            </For>
          </ul>
          <p class="text-[13px] text-muted-foreground">Hidden in this browser.</p>
        </div>
      </Show>
    </div>
  )
}
