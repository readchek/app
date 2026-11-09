import { expect, test } from "bun:test"
import { layoutFor } from "./modes.ts"

test("the reader's choice wins over everything", () => {
  expect(layoutFor("manga", "ttb", "scrolled")).toMatchObject({ flow: "paged", direction: "rtl" })
  expect(layoutFor("webtoon", "rtl", "paged")).toMatchObject({ flow: "scrolled" })
  expect(layoutFor("comic", "rtl", undefined)).toMatchObject({ flow: "paged", direction: "ltr" })
})

test("automatic scrolls what its source calls a vertical strip, without looking at pages", () => {
  expect(layoutFor("automatic", "ttb", undefined)).toEqual({
    flow: "scrolled",
    direction: "ltr",
    reads: "webtoon",
  })
})

test("automatic turns right to left when the source says so", () => {
  expect(layoutFor("automatic", "rtl", "scrolled")).toMatchObject({
    flow: "paged",
    direction: "rtl",
  })
})

test("automatic keeps to what a series' pages looked like before", () => {
  expect(layoutFor("automatic", null, "scrolled")).toMatchObject({ flow: "scrolled" })
  expect(layoutFor("automatic", "ltr", "paged")).toMatchObject({ flow: "paged", direction: "ltr" })
})

test("automatic looks at the pages only when nothing else says", () => {
  expect(layoutFor("automatic", null, undefined)).toEqual({
    flow: "automatic",
    direction: "ltr",
    reads: undefined,
  })
  expect(layoutFor("automatic", "ltr", undefined).flow).toBe("automatic")
})
