import { expect } from "@playwright/test"
import { menuTest as test, menuAssistantPath, waitForAssistantController } from "./helpers/assistant_ui.js"

// App-backed: composer `@` mention menu on /:cid/admin/assistant.
// Requires SKIP_AUTH=1. See spec/e2e/README.md.
const BASE = process.env.APP_BASE_URL
const MENTIONS = "/81721200/admin/modules/ai_assistant/messages/mentions"

test.use({ ignoreHTTPSErrors: true })

test.describe("assistant composer @ mentions", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("opens on @ and lists the tenant's mention candidates", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length, "tenant must have at least one mention candidate").toBeGreaterThan(0)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")

    await expect(composer).toHaveAttribute("aria-expanded", "true")
    await expect(listbox).toBeVisible()
    await expectMenuOnScreen(listbox)

    const options = listbox.getByRole("option")
    const shown = Math.min(mentions.length, 8)
    await expect(options).toHaveCount(shown)

    const first = mentions[0]
    await expect(options.first()).toContainText(first.label || first.name)
    await expect(options.first()).toHaveAttribute("aria-selected", "true")
    await expect(composer).toHaveAttribute("aria-activedescendant", "ai-assistant-mention-0")
  })

  test("filters as the query is typed", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const unique = uniqueMention(mentions)
    expect(unique, "need a candidate with a unique name prefix").toBeTruthy()

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, `@${unique.needle}`)

    await expect(listbox).toBeVisible()
    const options = listbox.getByRole("option")
    await expect(options).toHaveCount(1)
    await expect(options.first()).toContainText(unique.row.label || unique.row.name)
  })

  test("ArrowDown/ArrowUp move the highlight, Enter inserts @name", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(1)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox.getByRole("option")).toHaveCount(Math.min(mentions.length, 8))

    await composer.press("ArrowDown")
    await expect(listbox.getByRole("option").nth(1)).toHaveAttribute("aria-selected", "true")
    await expect(composer).toHaveAttribute("aria-activedescendant", "ai-assistant-mention-1")

    await composer.press("ArrowUp")
    await expect(listbox.getByRole("option").nth(0)).toHaveAttribute("aria-selected", "true")

    await composer.press("Enter")
    await expect(composer).toHaveValue(`@${mentions[0].name} `)
    await expect(listbox).toBeHidden()
    await expect(composer).toHaveAttribute("aria-expanded", "false")
  })

  test("Tab inserts the highlighted row", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(0)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    await composer.press("Tab")
    await expect(composer).toHaveValue(`@${mentions[0].name} `)
    await expect(listbox).toBeHidden()
  })

  test("clicking a row still inserts after the composer blurs", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(0)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    await composer.evaluate((node) => node.blur())
    await listbox.getByRole("option").first().click()
    await expect(composer).toHaveValue(`@${mentions[0].name} `)
    await expect(listbox).toBeHidden()
  })

  test("clicking a row inserts it and leaves the composer focused", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(1)

    const chosen = mentions[1]
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    await listbox.getByRole("option").nth(1).click()
    await expect(composer).toHaveValue(`@${chosen.name} `)
    await expect(listbox).toBeHidden()
    await expect(composer).toBeFocused()
  })

  test("Escape closes the menu without changing the typed text", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@inv")
    await expect(listbox).toBeVisible()

    await composer.press("Escape")
    await expect(listbox).toBeHidden()
    await expect(composer).toHaveValue("@inv")
    await expect(composer).toHaveAttribute("aria-expanded", "false")
  })

  test("shows the empty state when nothing matches", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@zzz-no-such-mention")

    await expect(listbox).toBeVisible()
    await expect(listbox.getByRole("option")).toHaveCount(1)
    await expect(listbox.getByRole("option")).toHaveText("No match. Try another name.")
    await expect(listbox.getByRole("option")).toHaveAttribute("aria-disabled", "true")
  })

  test("does not open when @ sits inside a word", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "hello@")
    await expect(listbox).toBeHidden()
    await expect(composer).toHaveAttribute("aria-expanded", "false")
  })

  test("opens after a space so @ can start a new mention", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(0)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "hello @")
    await expect(listbox).toBeVisible()
    await expect(listbox.getByRole("option").first()).toContainText(mentions[0].label || mentions[0].name)
  })

  test("inserts in the middle of a sentence and leaves the rest of the line", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(0)

    const { composer, listbox } = await openAssistant(page)
    await composer.click()
    await composer.evaluate((node) => {
      node.value = "Update @ soon"
      node.setSelectionRange(8, 8)
      node.dispatchEvent(new Event("input", { bubbles: true }))
    })
    await expect(listbox).toBeVisible()

    await composer.press("Enter")
    await expect(composer).toHaveValue(`Update @${mentions[0].name}  soon`)
    const caret = await composer.evaluate((node) => node.selectionStart)
    expect(caret).toBe(`Update @${mentions[0].name} `.length)
  })

  test("completes a flowchart whose name contains spaces", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const flowchart = mentions.find((row) => row.kind === "flowchart" && String(row.name).includes(" "))
    test.skip(!flowchart, "no spaced flowchart name in this tenant")

    const { composer, listbox } = await openAssistant(page)
    const prefix = flowchart.name.split(" ").slice(0, 2).join(" ")
    await typeIn(composer, `@${prefix}`)
    await expect(listbox.getByRole("option").filter({ hasText: flowchart.label || flowchart.name })).toBeVisible()

    await composer.press("Enter")
    await expect(composer).toHaveValue(`@${flowchart.name} `)
  })

  test("ArrowUp wraps to the last row", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(1)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    const shown = Math.min(mentions.length, 8)
    await expect(listbox.getByRole("option")).toHaveCount(shown)

    await composer.press("ArrowUp")
    await expect(listbox.getByRole("option").nth(shown - 1)).toHaveAttribute("aria-selected", "true")
    await expect(composer).toHaveAttribute("aria-activedescendant", `ai-assistant-mention-${shown - 1}`)
  })

  test("blur closes the menu, then a second @ mention can be added", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(1)

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    await page.locator("#assistant-conversation-panel header").click()
    await expect(listbox).toBeHidden()

    await typeIn(composer, `@${mentions[0].name} and @`)
    await expect(listbox).toBeVisible()
    await listbox.getByRole("option").nth(1).click()
    await expect(composer).toHaveValue(`@${mentions[0].name} and @${mentions[1].name} `)
  })

  test("labels each row with its translated kind", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const kinds = { entity: "Entity", flowchart: "Flowchart" }

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    // The menu is capped, so only the rows that fit carry a badge to check.
    const shown = mentions.slice(0, 8)
    const badges = await listbox.getByRole("option").evaluateAll(
      (rows) => rows.map((row) => row.lastElementChild.textContent)
    )
    expect(badges).toEqual(shown.map((row) => kinds[row.kind]))
  })

  // A flowchart is only ever reachable by typing: the unfiltered list is
  // capped, and this tenant has more entities than the cap.
  test("a kind pushed past the cap is still reachable by typing", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const beyond = mentions.slice(8)
    test.skip(!beyond.length, "every candidate fits in the menu")

    const target = beyond[0]
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, `@${target.name.slice(0, 6)}`)

    await expect(listbox.getByRole("option").filter({ hasText: target.label || target.name }).first()).toBeVisible()
  })

  test("keeps the menu on screen and clickable on a mobile viewport", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    expect(mentions.length).toBeGreaterThan(0)

    const { composer, listbox } = await openAssistant(page, { width: 390, height: 844 })
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()
    await expectMenuOnScreen(listbox)

    const option = listbox.getByRole("option").first()
    expect(await topmostAt(option), "something else is sitting on the first mention row").toBe(true)

    await option.click()
    await expect(composer).toHaveValue(`@${mentions[0].name} `)
  })

  // The menu is absolutely positioned inside the chat pane, and every ancestor
  // between it and the viewport clips its overflow.
  test("is not clipped by the chat pane on a short viewport", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page, { width: 1280, height: 560 })
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    const menu = await listbox.boundingBox()
    const pane = await page.locator("#assistant-conversation-panel").boundingBox()
    expect(menu.y, "the menu is cut off by the top of the chat pane").toBeGreaterThanOrEqual(pane.y - 1)
    expect(menu.y + menu.height).toBeLessThanOrEqual(pane.y + pane.height + 1)
    expect(await topmostAt(listbox.getByRole("option").first())).toBe(true)
  })

  test("stays open while the list is scrolled, and the row scrolled to still inserts", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    const list = page.locator("[data-ai-assistant-target='mentionList']")
    const scrollable = await list.evaluate((node) => node.scrollHeight > node.clientHeight + 1)
    test.skip(!scrollable, "the whole list fits, so there is nothing to scroll")

    await list.hover()
    await page.mouse.wheel(0, 200)
    await expect(listbox).toBeVisible()
    await expect.poll(() => list.evaluate((node) => node.scrollTop)).toBeGreaterThan(0)

    const shown = Math.min(mentions.length, 8)
    const last = listbox.getByRole("option").nth(shown - 1)
    await last.click()
    await expect(composer).toHaveValue(`@${mentions[shown - 1].name} `)
  })

  test("matches regardless of the case typed", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const lower = mentions.find((row) => row.name !== row.name.toUpperCase())
    test.skip(!lower, "every candidate name is already uppercase")

    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, `@${lower.name.slice(0, 4).toUpperCase()}`)

    await expect(listbox).toBeVisible()
    await expect(listbox.getByRole("option").filter({ hasText: lower.label || lower.name }).first()).toBeVisible()
  })

  test("reopens after Escape once typing continues", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@e")
    await composer.press("Escape")
    await expect(listbox).toBeHidden()

    await composer.pressSequentially("m", { delay: 20 })
    await expect(listbox).toBeVisible()
  })

  test("survives backspacing the query back to a bare @", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@empl")
    await expect(listbox).toBeVisible()

    for (let i = 0; i < 4; i += 1) await composer.press("Backspace")
    await expect(composer).toHaveValue("@")
    await expect(listbox.getByRole("option")).toHaveCount(Math.min(mentions.length, 8))
  })

  test("gets out of the way once the text stops looking like a name", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@add a due date field")
    await expect(listbox).toBeHidden()
    await expect(composer).toHaveAttribute("aria-expanded", "false")
  })

  test("points aria-activedescendant at a row that is really in the menu", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    for (const key of ["ArrowDown", "ArrowDown"]) {
      await composer.press(key)
      const resolved = await composer.evaluate((node) => {
        const id = node.getAttribute("aria-activedescendant")
        const row = id && document.getElementById(id)
        return { id, exists: Boolean(row), selected: row && row.getAttribute("aria-selected") }
      })
      expect(resolved.exists, `aria-activedescendant ${resolved.id} points at nothing`).toBe(true)
      expect(resolved.selected).toBe("true")
    }
  })

  // Stimulus reconnects the composer after a Turbo visit, and the mention
  // state is rebuilt from scratch with it.
  test("still completes after switching chats over Turbo", async ({ page, request }) => {
    const mentions = await loadMentions(request)
    const { composer, listbox } = await openAssistant(page)

    await page.locator("[data-ai-assistant-conversations-target='toggle']").click()
    const chat = page.locator("[data-ai-assistant-conversations-target='row'] a").filter({ hasText: "Browser fixture 2" })
    test.skip(!(await chat.count()), "this user has no saved chat to switch to")

    await chat.click()
    await expect(page.locator("#ai_assistant_composer")).toBeVisible()
    await waitForAssistantController(page)

    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()
    await listbox.getByRole("option").first().click()
    await expect(composer).toHaveValue(`@${mentions[0].name} `)
  })

  test("Shift+Enter breaks the line instead of completing", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await typeIn(composer, "@emp")
    await expect(listbox).toBeVisible()

    await composer.press("Shift+Enter")
    await expect(composer).toHaveValue("@emp\n")
  })

  // Enter at a pinyin candidate list commits the candidate. Acting on it would
  // complete a mention, or post the pinyin as the message.
  test("leaves Enter to the IME while a candidate is being composed", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await composer.click()
    const posted = watchPosts(page)

    const ime = await page.context().newCDPSession(page)
    await ime.send("Input.imeSetComposition", { text: "nihao", selectionStart: 5, selectionEnd: 5 })
    await expect(composer).toHaveValue("nihao")
    await expect(listbox).toBeHidden()

    await ime.send("Input.dispatchKeyEvent", {
      type: "rawKeyDown",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 13
    })
    await page.waitForTimeout(300)

    await expect(composer).toHaveValue("nihao")
    expect(await posted(), "the composing turn was sent as a message").toEqual([])
  })

  test("matches on what the IME committed, not on the pinyin", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page)
    await composer.click()

    const ime = await page.context().newCDPSession(page)
    await ime.send("Input.imeSetComposition", { text: "@emp", selectionStart: 4, selectionEnd: 4 })
    await expect(listbox).toBeHidden()

    await ime.send("Input.insertText", { text: "@employee" })
    await expect(listbox).toBeVisible()
    await expect(listbox.getByRole("option").first()).toContainText("employee")
  })

  test("leaves no horizontal overflow while the menu is open", async ({ page }) => {
    const { composer, listbox } = await openAssistant(page, { width: 390, height: 844 })
    await typeIn(composer, "@")
    await expect(listbox).toBeVisible()

    const geometry = await page.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth
    }))
    expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth + 1)
  })
})

async function loadMentions(request) {
  const response = await request.get(`${BASE}${MENTIONS}`, { headers: { Accept: "application/json" } })
  expect(response.ok()).toBeTruthy()
  const data = await response.json()
  return Array.isArray(data.mentions) ? data.mentions : []
}

async function openAssistant(page, viewport = { width: 1280, height: 800 }) {
  await page.setViewportSize(viewport)
  const response = await page.goto(`${BASE}${menuAssistantPath}`)
  expect(response?.ok()).toBeTruthy()

  const composer = page.locator("#ai_assistant_composer")
  await expect(composer).toBeVisible()
  await expect(composer).toBeEnabled()
  await waitForAssistantController(page)

  const listbox = page.locator("#ai_assistant_mention_menu")
  return { composer, listbox }
}

async function typeIn(composer, text) {
  // A fresh controller lazily fetches the real server candidates on input.
  // Await that completion as well as connection; do not seed its list in JS.
  await waitForAssistantController(composer.page())
  await composer.click()
  await composer.fill("")
  await composer.pressSequentially(text, { delay: 20 })
  if (/(^|\s)@/.test(text)) {
    await composer.page().waitForFunction(() => {
      const mount = document.querySelector("[data-controller~='ai-assistant']")
      const controller = mount && window.Stimulus?.getControllerForElementAndIdentifier(mount, "ai-assistant")
      return controller?.mentionsLoadedAt > 0 && !controller.mentionsRequest
    })
  }
}

// Records the URLs the page posts to, so a keystroke that must not send can
// be held to it.
function watchPosts(page) {
  const posts = []
  page.on("request", (request) => {
    if (request.method() === "POST") posts.push(new URL(request.url()).pathname)
  })
  return async () => posts
}

// Whether the element really receives the pointer at its own centre, rather
// than something invisible sitting over it.
async function topmostAt(locator) {
  return locator.evaluate((node) => {
    const box = node.getBoundingClientRect()
    const top = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)
    return top ? (node === top || node.contains(top) || top.contains(node)) : false
  })
}

async function expectMenuOnScreen(listbox) {
  const box = await listbox.boundingBox()
  expect(box, "mention menu must have a layout box").toBeTruthy()
  expect(box.height, "mention menu is clipped").toBeGreaterThan(24)
  expect(box.y, "mention menu is off the top of the viewport").toBeGreaterThanOrEqual(0)
}

function uniqueMention(mentions) {
  for (const row of mentions) {
    const name = String(row.name || "")
    for (let length = 3; length <= name.length; length += 1) {
      const needle = name.slice(0, length).toLowerCase()
      const hits = mentions.filter((candidate) =>
        `${candidate.name} ${candidate.label}`.toLowerCase().includes(needle)
      )
      if (hits.length === 1) return { row, needle }
    }
  }
  return null
}
