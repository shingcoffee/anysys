import { test, expect } from "@playwright/test"

// Tier C proof: the vendored SortableJS (which replaced the hand-rolled HTML5
// drag in countable_items_reorder_controller) actually reorders a list under
// real pointer events in a real browser — the exact thing happy-dom cannot verify.
const fixture = "http://127.0.0.1:3011/spec/e2e/fixtures/sortable_drag.html"

async function dragRow(page, fromSel, toSel) {
  const from = page.locator(fromSel)
  const to = page.locator(toSel)
  const fb = await from.boundingBox()
  const tb = await to.boundingBox()
  // Pointer-driven drag: press on the source handle, move across the target in
  // steps (SortableJS needs intermediate moves), drop past the target's midpoint.
  await page.mouse.move(fb.x + fb.width / 2, fb.y + fb.height / 2)
  await page.mouse.down()
  await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height / 2, { steps: 10 })
  await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height - 2, { steps: 5 })
  await page.mouse.up()
}

test("SortableJS reorders on real drag", async ({ page }) => {
  await page.goto(fixture)
  expect(await page.evaluate(() => window.__order())).toBe("abc")

  // Drag A's handle down past C.
  await dragRow(page, "li[data-id='a'] .handle", "li[data-id='c']")

  const after = await page.evaluate(() => window.__order())
  expect(after).not.toBe("abc")               // order changed => real drag worked
  expect(after.split("").sort().join("")).toBe("abc") // same three items, reordered
})
