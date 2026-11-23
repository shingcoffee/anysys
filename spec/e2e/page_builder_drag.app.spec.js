import { test, expect } from "@playwright/test"

// Tier C (app-backed): exercises controllers/page_builder/drag_engine.js (and its
// drop_resolver / drag_visuals / drop_mutations collaborators) in the REAL app.
//
// The page-builder canvas drag is a *Pointer Events* engine (pointerdown ->
// page-builder#dragPointerDown, then window pointermove/pointerup with an
// rAF tick loop that reads real layout via getBoundingClientRect). happy-dom
// cannot honestly drive this — there is no layout to measure. Playwright's
// real Chromium mouse API emits the full pointerdown/pointermove/pointerup
// sequence, which is exactly what the engine listens for.
//
// Field cards are rendered client-side by field_manager.createFieldCard as
//   <div class="field-card" data-field-id data-drag-kind="move"
//        data-action="... pointerdown->page-builder#dragPointerDown ...">
// inside [data-page-builder-target="fieldsContainer"]. A successful drag
// reorders those cards (drop_mutations mutates the field model + re-renders),
// so the observable proof is: the sequence of data-field-id values changes.
//
// Gated: requires a running app with a seeded page that has >= 2 fields.
// Set APP_BASE_URL (e.g. http://127.0.0.1:3001). Override the page with
// PAGE_EDIT_PATH if id 1 under customer 81721200 is not a suitable fixture.
const BASE = process.env.APP_BASE_URL
const EDIT_PATH = process.env.PAGE_EDIT_PATH || "/81721200/admin/maintenance/pages/1/edit"

test.describe("page builder field drag reorder (drag_engine)", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("pointer-dragging a field card reorders the canvas", async ({ page }) => {
    await page.goto(BASE + EDIT_PATH)

    // Cards render client-side once the controller boots; wait for them.
    const cardSel = '[data-page-builder-target="fieldsContainer"] .field-card[data-field-id]'
    await page.waitForSelector(cardSel, { timeout: 15000 })

    const order = async () =>
      page.$$eval(cardSel, (els) => els.map((e) => e.getAttribute("data-field-id")))

    const before = await order()
    test.skip(before.length < 2, "need at least two fields on the page to reorder")

    const cards = page.locator(cardSel)
    const first = cards.first()
    const last = cards.last()
    const fb = await first.boundingBox()
    const tb = await last.boundingBox()

    // Pointer-driven drag: the engine arms on pointerdown, starts the drag once
    // the pointer moves past MOVE_THRESHOLD (5px), resolves the drop slot from
    // the ghost centre on each rAF tick, and mutates on pointerup. Move in steps
    // so intermediate pointermove ticks run, and drop past the target's far edge
    // so the resolver places the card AFTER the last field.
    await page.mouse.move(fb.x + fb.width / 2, fb.y + fb.height / 2)
    await page.mouse.down()
    await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height / 2, { steps: 15 })
    await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height - 2, { steps: 8 })
    await page.mouse.up()

    // The re-render is synchronous on drop, but poll to be robust against rAF.
    await expect.poll(async () => (await order()).join(",")).not.toBe(before.join(","))

    const after = await order()
    expect(after.slice().sort()).toEqual(before.slice().sort()) // same fields, reordered
    expect(after[0]).not.toBe(before[0])                        // head actually moved
  })
})
