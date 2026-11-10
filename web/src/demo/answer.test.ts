import { expect, test } from "bun:test"
import { type Catalog, answer } from "./answer.ts"

const chapter = (id: string) => ({ id })

const catalog = {
  sites: {
    comic: {
      listing: [],
      series: {},
      chapters: {
        strip: {
          items: [chapter("one"), chapter("two"), chapter("three"), chapter("four")],
          chapterCount: 4,
          preferredGroup: null,
        },
      },
      contents: { one: { pages: [] }, two: { pages: [] } },
    },
  },
} as unknown as Catalog

const backend = {
  catalog,
  positions: { all: () => ({}), save: () => {} },
  file: async () => new Response(null, { status: 404 }),
}

async function chapters(query = "") {
  const response = await answer(
    new Request(`https://demo.test/api/v1/me/extensions/comic/chapters?seriesId=strip${query}`),
    backend,
  )
  return (await response.json()) as { items: { id: string }[]; total: number; chapterCount: number }
}

test("lists only the chapters the snapshot kept", async () => {
  const page = await chapters()
  expect(page.items.map((item) => item.id)).toEqual(["one", "two"])
  expect(page.total).toBe(2)
  expect(page.chapterCount).toBe(2)
})

test("has nothing after the last chapter kept", async () => {
  expect((await chapters("&after=two&limit=1")).items).toEqual([])
  expect((await chapters("&after=two&order=desc&limit=1")).items.map((item) => item.id)).toEqual([
    "one",
  ])
})
