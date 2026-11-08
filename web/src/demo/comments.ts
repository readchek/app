// Sample readers' comments for the demo, so everyone trying it, App Review
// included, can see the comments panel with replies, spoilers and its
// menu. They're written for the demo and signed as samples, never quoted
// from a real site. The real server passes on what an extension's site
// shows; see readchek/chek's /api/v1/me/extensions/{id}/comments.

/** The demo source that shows comments, and how it sorts them. */
export const COMMENTING = "page.chek.peppercarrot"
export const ORDERS = ["top", "newest"]

type Run = {
  text: string
  bold?: boolean
  italic?: boolean
  spoiler?: boolean
  quote?: boolean
}

type Sample = {
  id: string
  name: string
  badge?: string
  /** Minutes before the demo is opened. */
  ago: number
  score: number
  body: Run[]
  spoiler?: boolean
  edited?: boolean
  replies?: Sample[]
  replyTo?: string
}

const SAMPLES: Sample[] = [
  {
    id: "s1",
    name: "Sample reader · Ana",
    ago: 120,
    score: 41,
    body: [
      { text: "The colors in this one are " },
      { text: "gorgeous", bold: true },
      { text: ". I keep going back to the last page." },
    ],
    replies: [
      {
        id: "s1r1",
        name: "Sample reader · Mei",
        ago: 60,
        score: 9,
        body: [{ text: "Same. That last spread is my new wallpaper." }],
      },
      {
        id: "s1r2",
        name: "Sample reader · Sam",
        ago: 40,
        score: 2,
        replyTo: "Sample reader · Mei",
        body: [{ text: "The artist shares the making-of on their site too." }],
      },
    ],
  },
  {
    id: "s2",
    name: "Sample reader · Tomás",
    badge: "Sample",
    ago: 300,
    score: 18,
    body: [
      { text: "These comments are samples written for the Chek demo. " },
      {
        text: "On your own server they come from the site your extension reads.",
        italic: true,
      },
    ],
  },
  {
    id: "s3",
    name: "Sample reader · Jun",
    ago: 360,
    score: 12,
    spoiler: true,
    body: [{ text: "Didn't see that ending coming at all." }],
    replies: [
      {
        id: "s3r1",
        name: "Sample reader · Ana",
        ago: 300,
        score: 4,
        body: [{ text: "Right? Reread it straight away." }],
      },
    ],
  },
  {
    id: "s4",
    name: "Sample reader · Priya",
    ago: 1440,
    score: 7,
    body: [
      { text: "Did anyone else notice " },
      { text: "the cat in the background of every page", spoiler: true },
      { text: "? Rereading now." },
    ],
  },
  {
    id: "s5",
    name: "Sample reader · Leo",
    ago: 1500,
    score: 3,
    edited: true,
    body: [{ text: "Short one, but the pacing works." }],
  },
]

function stamp(ago: number): string {
  return new Date(Date.now() - ago * 60_000).toISOString()
}

// The episode's own page stands in for each comment's place on the site, so the
// demo shows Report and Open as a real source does.
function thread(params: URLSearchParams): string {
  const chapter = encodeURIComponent(params.get("chapterId") ?? "")
  return `https://www.peppercarrot.com/en/webcomic/${chapter}`
}

function comment(sample: Sample, url: string) {
  return {
    id: sample.id,
    author: { name: sample.name, avatarUrl: null, badge: sample.badge ?? null },
    published: stamp(sample.ago),
    edited: sample.edited ?? false,
    body: sample.body,
    images: [],
    spoiler: sample.spoiler ?? false,
    score: sample.score,
    replyTo: sample.replyTo ?? null,
    replyCount: sample.replies?.length ?? 0,
    url,
  }
}

/** The demo's answer to a comments route, or null for another route. */
export function answerComments(rest: string, params: URLSearchParams): Response | null {
  const reply = (body: unknown) =>
    new Response(JSON.stringify(body), {
      headers: { "Content-Type": "application/json" },
    })
  switch (rest) {
    case "comments/summary":
      return reply({ count: SAMPLES.length, url: thread(params) })
    case "comments": {
      const order = params.get("order") ?? ORDERS[0]
      const items = [...SAMPLES]
      if (order === "newest") items.sort((a, b) => a.ago - b.ago)
      return reply({
        items: items.map((sample) => comment(sample, thread(params))),
        next: null,
        total: SAMPLES.length,
      })
    }
    case "comments/replies": {
      const parent = SAMPLES.find((sample) => sample.id === params.get("commentId"))
      const replies = parent?.replies ?? []
      return reply({
        items: replies.map((sample) => comment(sample, thread(params))),
        next: null,
        total: replies.length,
      })
    }
  }
  return null
}
