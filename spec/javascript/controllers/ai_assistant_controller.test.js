import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/ai_assistant_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const flush = () => new Promise((resolve) => setTimeout(resolve, 0))

const IDLE_PLACEHOLDER = "Ask anything"
const EXHAUSTED_LABEL = "This chat has reached its limit. Start a new chat to continue."
const CONNECTION_LOST_LABEL = "Lost contact with the server. Reload the page to see the reply."
const APPLY_LABEL = "Apply it"
const APPLYING_LABEL = "Applying it…"
const SUPERSEDED_LABEL = "A newer proposal replaced this one."
// Mirrors ai_assistant.assistant.plan.apply_reply, which has to be a token
// PendingConfirmation.explicit_confirmation? already recognises.
const CONFIRM_PHRASE = "yes"

function panelHtml(overrides = {}) {
  const attr = (name) => `data-ai-assistant-${name.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)}-value`
  const value = (name, fallback) => {
    if (Object.prototype.hasOwnProperty.call(overrides, name)) return `${attr(name)}="${overrides[name]}"`
    return fallback == null ? "" : `${attr(name)}="${fallback}"`
  }

  const thread = overrides.omitThread
    ? ""
    : `<div data-ai-assistant-target="thread" data-action="scroll->ai-assistant#threadScrolled wheel->ai-assistant#userScrolled touchstart->ai-assistant#userScrolled touchmove->ai-assistant#userScrolled" style="height:40px;overflow:auto">${overrides.threadInner ?? ""}</div>`
  const composer = overrides.omitComposer
    ? ""
    : `<textarea data-ai-assistant-target="composer" placeholder="${IDLE_PLACEHOLDER}" aria-expanded="false" data-action="keydown->ai-assistant#keydown input->ai-assistant#compose compositionend->ai-assistant#compose blur->ai-assistant#closeMentions">${overrides.value ?? ""}</textarea>`
  const sendButton = overrides.omitButton
    ? ""
    : `<button type="button" data-ai-assistant-target="sendButton" data-action="click->ai-assistant#send">Send</button>`
  const stopButton = overrides.omitStop
    ? ""
    : `<button type="button" class="hidden" data-ai-assistant-target="stopButton" data-action="click->ai-assistant#stop">Stop</button>`
  const regenerateButton = overrides.omitRegenerate
    ? ""
    : `<button type="button" data-ai-assistant-target="regenerateButton" data-action="click->ai-assistant#regenerate">Regenerate</button>`
  const jumpButton = overrides.omitJump
    ? ""
    : `<button type="button" class="hidden" data-ai-assistant-target="jumpButton" data-action="click->ai-assistant#jumpToLatest">Jump to latest</button>`
  const strayCopyButton = overrides.strayCopy
    ? `<button type="button" aria-label="Copy" data-action="click->ai-assistant#copy"></button>`
    : ""
  const images = overrides.omitImages
    ? ""
    : `<input type="file" data-ai-assistant-target="images" data-action="change->ai-assistant#pickImages">`
  const previews = overrides.omitPreviews
    ? ""
    : `<ul data-ai-assistant-target="previews"></ul>`
  const error = overrides.omitError
    ? ""
    : `<p class="hidden" data-ai-assistant-target="error"></p>`
  const prompt = overrides.prompt == null
    ? ""
    : `<button type="button" data-action="click->ai-assistant#usePrompt" ${overrides.promptData ? `data-prompt="${overrides.promptData}"` : ""}>${overrides.prompt}</button>`
  const turnsHint = overrides.omitTurnsHint
    ? ""
    : `<p class="hidden" data-ai-assistant-target="turnsHint"></p>`
  // Omitted by default, which is what an idle panel looks like. `running` opts
  // in; `runningFlagUntargeted` drops the Stimulus target to exercise the
  // id lookup the server's replacement broadcast relies on.
  const runningFlag = overrides.running == null
    ? ""
    : `<div id="ai_assistant_running" ${
        overrides.runningFlagUntargeted ? "" : `data-ai-assistant-target="runningFlag"`
      } data-running="${overrides.running}" hidden></div>`
  const mentionKinds = `data-ai-assistant-mention-kinds-value='{"entity":"Entity","flowchart":"Flowchart"}'`
  const mentionEmpty = `data-ai-assistant-mention-empty-label-value="No match"`
  const mentionMenu = overrides.omitMentionMenu
    ? ""
    : `<div class="hidden" data-ai-assistant-target="mentionMenu" role="listbox" data-action="mousedown->ai-assistant#preventBlur pointerdown->ai-assistant#preventBlur">${
        overrides.omitMentionList ? "" : `<ul data-ai-assistant-target="mentionList" role="presentation"></ul>`
      }</div>`
  const newChatButton = overrides.omitNewChat
    ? ""
    : `<button type="button" class="hidden" data-ai-assistant-target="newChatButton" data-action="click->ai-assistant#newChat">Start a new chat</button>`
  const values = [
    value("stopUrl", "/messages/stop"),
    value("regenerateUrl", "/messages/regenerate"),
    value("conversationId", "conv-1"),
    // Disarmed by default so ordinary examples never leave a three-minute
    // timer behind; the watchdog examples opt in with their own budget.
    value("watchdogMs", 0),
    value("cooldownMs", 0),
    value("turnsRemaining"),
    value("turnsWarningAt"),
    value("mentionsUrl", "/messages/mentions"),
    // Deliberately unlike the controller's own defaults, so a test that reads
    // one of these back proves the server's translation was used.
    value("proposalApplyLabel", APPLY_LABEL),
    value("proposalApplyingLabel", APPLYING_LABEL),
    value("proposalSupersededLabel", SUPERSEDED_LABEL),
    value("questionsSendLabel", "Send answers"),
    value("questionsSendingLabel", "Sending…"),
    mentionKinds,
    mentionEmpty
  ].join(" ")
  return `<div data-controller="ai-assistant" data-ai-assistant-url-value="/messages" ${values}>${thread}${mentionMenu}${composer}${sendButton}${stopButton}${regenerateButton}${jumpButton}${strayCopyButton}${images}${previews}${error}${prompt}${turnsHint}${newChatButton}${runningFlag}</div>`
}

const errorIn = (element) => element.querySelector("[data-ai-assistant-target='error']")
const composerIn = (element) => element.querySelector("textarea")
const threadIn = (element) => element.querySelector("[data-ai-assistant-target='thread']")
const sendIn = (element) => element.querySelector("[data-ai-assistant-target='sendButton']")
const jumpIn = (element) => element.querySelector("[data-ai-assistant-target='jumpButton']")
const jumpVisible = (element) => !jumpIn(element).classList.contains("hidden")
const regenerateIn = (element) => element.querySelector("[data-ai-assistant-target='regenerateButton']")

// happy-dom reports a zero-height layout, so the transcript's geometry has to
// be declared outright. `scrollTop` stays a real property, which is what lets
// the controller's own scroll writes be observed.
function sizeThread(element, { scrollHeight = 1000, clientHeight = 400, scrollTop = 600 } = {}) {
  const thread = threadIn(element)
  Object.defineProperty(thread, "scrollHeight", { value: scrollHeight, configurable: true })
  Object.defineProperty(thread, "clientHeight", { value: clientHeight, configurable: true })
  thread.scrollTop = scrollTop
  return thread
}

// Types into the composer the way the browser does: set the value, place the
// caret, fire `input`, then let the mention fetch settle.
async function type(element, value, caret = value.length) {
  const composer = element.querySelector("textarea")
  composer.value = value
  composer.setSelectionRange(caret, caret)
  composer.dispatchEvent(new Event("input", { bubbles: true }))
  await flush()
  await flush()
}

const menuIn = (element) => element.querySelector("[data-ai-assistant-target='mentionMenu']")
const menuOpen = (element) => !menuIn(element).classList.contains("hidden")
const optionsIn = (element) => Array.from(element.querySelectorAll("[role='option']"))
const optionLabels = (element) => optionsIn(element).map((option) => option.textContent)
const selectedIn = (element) => optionsIn(element).find((option) => option.getAttribute("aria-selected") === "true")

function pressKey(element, key, { shiftKey = false, isComposing = false } = {}) {
  const event = new Event("keydown", { bubbles: true, cancelable: true })
  event.key = key
  event.shiftKey = shiftKey
  event.isComposing = isComposing
  element.querySelector("textarea").dispatchEvent(event)
  return { defaultPrevented: event.defaultPrevented }
}

const MENTIONS = [
  { kind: "entity", name: "Invoice", label: "Invoices" },
  { kind: "entity", name: "Purchase Order", label: "Purchase Orders" },
  { kind: "flowchart", name: "Issue invoice", label: "Issue invoice" }
]

function mockMentions(rows = MENTIONS) {
  const fetchMock = vi.fn().mockImplementation((url) => Promise.resolve({
    status: 200,
    ok: true,
    json: async () => (String(url).endsWith("/mentions") ? { mentions: rows } : {})
  }))
  vi.stubGlobal("fetch", fetchMock)
  return fetchMock
}

const turnsHintIn = (element) => element.querySelector("[data-ai-assistant-target='turnsHint']")
const hintState = (element) => ({
  text: turnsHintIn(element).textContent,
  hidden: turnsHintIn(element).classList.contains("hidden")
})

// Mirrors ProposedChangesComponent's root and footer. Only the attributes the
// controller reaches for are reproduced: the card itself is server-rendered.
function proposalHtml({
  state = "pending",
  reply = CONFIRM_PHRASE,
  applyButton = true,
  refineButton = true,
  applyLabel = true,
  note = true,
  messageId = null,
  discard = false
} = {}) {
  const replyParam = reply == null ? "" : ` data-ai-assistant-reply-param="${reply}"`
  const messageParam = messageId == null ? "" : ` data-ai-assistant-message-id-param="${messageId}"`
  const apply = applyButton
    ? `<button type="button" data-proposal-apply data-action="click->ai-assistant#applyProposal"${replyParam}${messageParam}>${
        applyLabel ? `<span data-proposal-apply-label>${APPLY_LABEL}</span>` : APPLY_LABEL
      }</button>`
    : ""
  const discardBtn = discard === "button"
    ? `<button type="button" data-proposal-discard>Discard</button>`
    : discard
      ? `<span data-proposal-discard><form><button type="submit">Discard</button></form></span>`
      : ""
  const refine = refineButton
    ? `<button type="button" data-proposal-refine data-action="click->ai-assistant#refineProposal">Tell me what to change</button>`
    : ""
  const noteSlot = note ? `<p class="hidden" data-proposal-note></p>` : ""
  return `<section data-proposal="${state}" aria-label="Proposed changes">${apply}${discardBtn}${refine}${noteSlot}</section>`
}

function questionsHtml({
  state = "open",
  sendLabel = true,
  answered = true,
  subtitle = true,
  footer = true,
  inputs = true,
  fieldset = true
} = {}) {
  const subtitleSlot = subtitle ? `<p data-questions-subtitle>Pick an answer</p>` : ""
  const answeredSlot = answered ? `<p class="hidden" data-questions-answered>Answered below.</p>` : ""
  const field = fieldset
    ? `<fieldset data-questions-fieldset data-question-type="text" data-question-prompt="Hours">${
        inputs
          ? `<input type="text" data-questions-input data-question-text value="Mon"><div data-questions-input><input type="text" value="other"></div>`
          : ""
      }<label><input type="radio" value="A" checked><input type="checkbox" value="B" checked></label></fieldset>`
    : ""
  const send = sendLabel
    ? `<button type="button"><span data-questions-send-label>Send answers</span></button>`
    : `<button type="button">Send answers</button>`
  const footerSlot = footer ? `<footer data-questions-footer>${send}<button type="button">Skip</button></footer>` : ""
  return `<section data-questions="${state}">${subtitleSlot}${answeredSlot}${field}${footerSlot}</section>`
}

// Mirrors MessageComponent: the copy button lives inside the message it copies,
// and a proposal panel sits below the bubble it belongs to.
function messageHtml({ role = "assistant", body = "Hi there", text, copyButton = true, icons = true, proposal } = {}) {
  const bodyAttr = body == null ? "" : ` data-body="${body}"`
  const icon = icons ? `<svg data-copy-idle></svg><svg class="hidden" data-copy-done></svg>` : ""
  const button = copyButton
    ? `<button type="button" aria-label="Copy" data-action="click->ai-assistant#copy">${icon}</button>`
    : ""
  return `<div data-role="${role}"${bodyAttr}>${button}<span>${text ?? body ?? ""}</span>${proposal ?? ""}</div>`
}

const panelsIn = (element) => Array.from(element.querySelectorAll("[data-proposal]"))
const applyIn = (panel) => panel.querySelector("[data-proposal-apply]")
const refineIn = (panel) => panel.querySelector("[data-proposal-refine]")
const noteIn = (panel) => panel.querySelector("[data-proposal-note]")
const applyLabelIn = (panel) => panel.querySelector("[data-proposal-apply-label]")
const discardHostIn = (panel) => panel.querySelector("[data-proposal-discard]")
const discardButtonIn = (panel) => {
  const host = discardHostIn(panel)
  if (!host) return null
  return host.matches("button") ? host : host.querySelector("button")
}
const cardsIn = (element) => Array.from(element.querySelectorAll("[data-questions]"))

const copyButtonIn = (element) => element.querySelector("[data-role] button")
const iconState = (button) => ({
  idle: !button.querySelector("[data-copy-idle]").classList.contains("hidden"),
  done: !button.querySelector("[data-copy-done]").classList.contains("hidden")
})

function mockFetch(status, { reject = false, json = {}, jsonThrows = false } = {}) {
  const fetchMock = vi.fn().mockImplementation(() => {
    if (reject) return Promise.reject(new Error("network"))
    return Promise.resolve({
      status,
      ok: status >= 200 && status < 300,
      json: jsonThrows ? async () => { throw new Error("no json") } : async () => json
    })
  })
  vi.stubGlobal("fetch", fetchMock)
  return fetchMock
}

function file(name, type, size) {
  return new File([new Uint8Array(size)], name, { type })
}

describe("ai-assistant controller", () => {
  beforeEach(() => {
    document.head.innerHTML = ""
    vi.stubGlobal("URL", { createObjectURL: vi.fn(() => "blob:preview"), revokeObjectURL: vi.fn() })
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    document.head.innerHTML = ""
  })

  it("announces selected-thread updates and clearing from its own panel", async () => {
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const controller = controllerFor(application, element, "ai-assistant")
    const changed = vi.fn()
    element.addEventListener("ai-assistant:conversationChanged", event => changed({ target: event.target, detail: event.detail }))

    controller.conversationIdValue = "conv-88"
    await tick()
    expect(changed).toHaveBeenCalledOnce()
    expect(changed.mock.calls[0][0].target).toBe(element)
    expect(changed.mock.calls[0][0].detail).toEqual({ conversationId: "conv-88" })

    controller.conversationIdValue = ""
    await tick()
    expect(changed.mock.calls.at(-1)[0].detail).toEqual({ conversationId: "" })
  })

  it("posts the trimmed composer body as FormData and clears the field on 202", async () => {
    const fetchMock = mockFetch(202)
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "  hello  " }))
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, options] = fetchMock.mock.calls[0]
    expect(url).toBe("/messages")
    expect(options.method).toBe("POST")
    expect(options.headers["X-CSRF-Token"]).toBe("")
    expect(options.headers["Content-Type"]).toBeUndefined()
    expect(options.body).toBeInstanceOf(FormData)
    expect(options.body.get("body")).toBe("hello")
    expect(element.querySelector("textarea").value).toBe("")
  })

  it("stays busy after 202 until an assistant bubble arrives", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(ctrl.busy).toBe(true)
    expect(element.querySelector("[data-ai-assistant-target='sendButton']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-ai-assistant-target='stopButton']").classList.contains("hidden")).toBe(false)

    const bubble = document.createElement("div")
    bubble.setAttribute("data-role", "assistant")
    bubble.textContent = "Hi"
    element.querySelector("[data-ai-assistant-target='thread']").appendChild(bubble)
    await tick()
    expect(ctrl.busy).toBe(false)
    expect(element.querySelector("[data-ai-assistant-target='sendButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-ai-assistant-target='stopButton']").classList.contains("hidden")).toBe(true)
    element.querySelector("[data-ai-assistant-target='thread']").appendChild(document.createElement("div"))
    await tick()
    expect(ctrl.busy).toBe(false)
  })

  it("clears busy when a wrapper containing an assistant bubble is appended", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    const wrapper = document.createElement("div")
    wrapper.innerHTML = `<div data-role="assistant">Hi</div>`
    element.querySelector("[data-ai-assistant-target='thread']").appendChild(wrapper)
    await tick()
    expect(ctrl.busy).toBe(false)
  })

  it("ignores non-element mutations and user bubbles while busy", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    const thread = element.querySelector("[data-ai-assistant-target='thread']")
    thread.appendChild(document.createTextNode("noise"))
    const user = document.createElement("div")
    user.setAttribute("data-role", "user")
    thread.appendChild(user)
    await tick()
    expect(ctrl.busy).toBe(true)
  })

  it("clears busy when the running flag is replaced with false", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    const flag = document.createElement("div")
    flag.id = "ai_assistant_running"
    flag.setAttribute("data-running", "false")
    element.appendChild(flag)
    await tick()
    expect(ctrl.busy).toBe(false)
  })

  it("clears busy when a wrapper contains a stopped running flag", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    const wrapper = document.createElement("div")
    wrapper.innerHTML = `<div id="ai_assistant_running" data-running="false"></div>`
    element.appendChild(wrapper)
    await tick()
    expect(ctrl.busy).toBe(false)
  })

  it("does not clear busy when the running flag is still true", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    const flag = document.createElement("div")
    flag.id = "ai_assistant_running"
    flag.setAttribute("data-running", "true")
    element.appendChild(flag)
    await tick()
    expect(ctrl.busy).toBe(true)
  })

  it("does not post when the composer is blank and no files are selected", async () => {
    const fetchMock = mockFetch(202)
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "   " }))
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("sends files without a body", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.files = [file("shot.png", "image/png", 4)]
    ctrl.send()
    await flush()
    expect(fetchMock.mock.calls[0][1].body.get("body")).toBe("")
    expect(fetchMock.mock.calls[0][1].body.getAll("images[]")).toHaveLength(1)
    expect(ctrl.files).toEqual([])
  })

  it("does not send when the selected files are invalid", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hello" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.files = [file("note.txt", "text/plain", 4)]
    ctrl.send()
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toContain("not allowed")
  })

  it("ignores a second send while a request is in flight", async () => {
    let resolveFetch
    const fetchMock = vi.fn().mockImplementation(() => new Promise((resolve) => { resolveFetch = resolve }))
    vi.stubGlobal("fetch", fetchMock)
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "one" }))
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    element.querySelector("textarea").value = "two"
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    expect(fetchMock).toHaveBeenCalledOnce()
    resolveFetch({ status: 202, ok: true, json: async () => ({}) })
    await flush()
  })

  it("restores the composer when the response is not ok", async () => {
    mockFetch(422)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "keep me" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(element.querySelector("textarea").value).toBe("keep me")
    expect(ctrl.busy).toBe(false)
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toBe("Could not send the message.")
  })

  it("shows server send errors on the attachError alert", async () => {
    mockFetch(429, { json: { errors: ["Rate limited.", ""] } })
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "keep me" }))
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toBe("Rate limited.")
    expect(element.querySelector("[data-ai-assistant-target='error']").classList.contains("hidden")).toBe(false)
  })

  it("shows a string send error and the default when the body is unusable", async () => {
    mockFetch(403, { json: { errors: "Module unavailable." } })
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "keep me" }))
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toBe("Module unavailable.")

    mockFetch(422, { json: { errors: [""] } })
    const again = await mountController("ai-assistant", Controller, panelHtml({ value: "keep me" }))
    await click(again.element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(again.element.querySelector("[data-ai-assistant-target='error']").textContent).toBe("Could not send the message.")

    mockFetch(422, { jsonThrows: true })
    const broken = await mountController("ai-assistant", Controller, panelHtml({ value: "keep me" }))
    await click(broken.element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(broken.element.querySelector("[data-ai-assistant-target='error']").textContent).toBe("Could not send the message.")
  })

  it("restores the composer when fetch rejects", async () => {
    mockFetch(0, { reject: true })
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "draft" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(element.querySelector("textarea").value).toBe("draft")
    expect(ctrl.busy).toBe(false)
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toBe("Could not send the message.")
  })

  it("does not throw when send fails without an attachError target", async () => {
    mockFetch(422, { json: { errors: ["Nope"] } })
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ value: "keep me", omitError: true })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(ctrl.busy).toBe(false)
  })

  it("posts stop and ignores stop when the URL is blank", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "x" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(element.querySelector("[data-ai-assistant-target='stopButton']"))
    expect(fetchMock).toHaveBeenCalledWith("/messages/stop", expect.objectContaining({ method: "POST" }))
    ctrl.stopUrlValue = ""
    await click(element.querySelector("[data-ai-assistant-target='stopButton']"))
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it("stop() without an event still posts", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.stop()
    await flush()
    expect(fetchMock).toHaveBeenCalledWith("/messages/stop", expect.objectContaining({ method: "POST" }))
  })

  it("keeps stop available when the stop request rejects", async () => {
    mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "go" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.send()
    await flush()
    expect(ctrl.busy).toBe(true)
    mockFetch(0, { reject: true })
    expect(() => ctrl.stop()).not.toThrow()
    await flush()
    expect(ctrl.busy).toBe(true)
  })

  it("copies the body of the message the button belongs to", async () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", { clipboard: { writeText } })
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ threadInner: messageHtml({ body: "First" }) + messageHtml({ body: "Second" }) })
    )
    const first = element.querySelectorAll("[data-role] button")[0]
    await click(first)
    await flush()
    expect(writeText).toHaveBeenCalledWith("First")
    expect(first.getAttribute("aria-label")).toBe("Copied")
    expect(iconState(first)).toEqual({ idle: false, done: true })
  })

  it("restores the copy button after the confirmation lapses", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", { clipboard: { writeText } })
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ threadInner: messageHtml({}) }))
    const button = copyButtonIn(element)
    await click(button)
    await flush()
    // A second copy replaces the pending restore rather than stacking one.
    await click(button)
    await flush()
    expect(iconState(button)).toEqual({ idle: false, done: true })
    await vi.advanceTimersByTimeAsync(1700)
    expect(button.getAttribute("aria-label")).toBe("Copy")
    expect(iconState(button)).toEqual({ idle: true, done: false })
    vi.useRealTimers()
  })

  it("keeps working when the button carries no icons", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    vi.stubGlobal("navigator", { clipboard: { writeText: vi.fn().mockResolvedValue() } })
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ threadInner: messageHtml({ icons: false }) })
    )
    const button = copyButtonIn(element)
    await click(button)
    await flush()
    expect(button.getAttribute("aria-label")).toBe("Copied")
    await vi.advanceTimersByTimeAsync(1700)
    expect(button.getAttribute("aria-label")).toBe("Copy")
    vi.useRealTimers()
  })

  it("clears a pending restore when the controller disconnects", async () => {
    vi.stubGlobal("navigator", { clipboard: { writeText: vi.fn().mockResolvedValue() } })
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ threadInner: messageHtml({}) }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    await click(copyButtonIn(element))
    await flush()
    expect(ctrl.copyTimer).toBeTruthy()
    ctrl.disconnect()
    expect(ctrl.copyTimer).toBeNull()
  })

  it("falls back to text content and the failed label when clipboard is missing", async () => {
    vi.stubGlobal("navigator", {})
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ threadInner: messageHtml({ role: "user", body: null, text: "Plain" }) })
    )
    const button = copyButtonIn(element)
    await click(button)
    await flush()
    expect(button.getAttribute("aria-label")).toBe("Could not copy")
    expect(iconState(button)).toEqual({ idle: true, done: false })
  })

  it("uses the failed label when clipboard write rejects", async () => {
    vi.stubGlobal("navigator", { clipboard: { writeText: vi.fn().mockRejectedValue(new Error("denied")) } })
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ threadInner: messageHtml({ body: "x" }) })
    )
    const button = copyButtonIn(element)
    await click(button)
    await flush()
    expect(button.getAttribute("aria-label")).toBe("Could not copy")
  })

  it("copies the latest message when the button is not tied to one", async () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", { clipboard: { writeText } })
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ strayCopy: true, threadInner: messageHtml({ body: "kept", copyButton: false }) })
    )
    await click(element.querySelector("div > button[aria-label='Copy']"))
    await flush()
    expect(writeText).toHaveBeenCalledWith("kept")
  })

  it("copy is a no-op without any message to copy", async () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", { clipboard: { writeText } })
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ omitThread: true }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    expect(() => ctrl.copy({ preventDefault: vi.fn() })).not.toThrow()

    const withThread = await mountController("ai-assistant", Controller, panelHtml({ threadInner: "" }))
    controllerFor(withThread.application, withThread.element, "ai-assistant").copy()
    expect(writeText).not.toHaveBeenCalled()
  })

  it("copies an empty body without a button to confirm on", async () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", { clipboard: { writeText } })
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ threadInner: messageHtml({ role: "user", body: null, text: "", copyButton: false }) })
    )
    controllerFor(application, element, "ai-assistant").copy()
    await flush()
    expect(writeText).toHaveBeenCalledWith("")
  })

  it("opens the file picker and commits selected images", async () => {
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    const input = element.querySelector("[data-ai-assistant-target='images']")
    const clickSpy = vi.spyOn(input, "click").mockImplementation(() => {})
    ctrl.attach({ preventDefault: vi.fn() })
    expect(clickSpy).toHaveBeenCalled()
    clickSpy.mockRestore()
    Object.defineProperty(input, "files", { value: [file("shot.png", "image/png", 4)], configurable: true })
    ctrl.pickImages()
    expect(element.querySelector("[data-ai-assistant-target='previews'] img").getAttribute("src")).toBe("blob:preview")
    // The remove control is a styled chip affordance, not a bare glyph.
    const remove = element.querySelector("[data-ai-assistant-target='previews'] button")
    expect(remove.getAttribute("aria-label")).toBe("Remove image")
    expect(remove.className).toContain("rounded-full")
    expect(remove.className).toContain("focus-visible:ring-accent")
    remove.click()
    expect(ctrl.files).toEqual([])
  })

  it("keeps previous files when a new selection is invalid", async () => {
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    const good = file("shot.png", "image/png", 4)
    ctrl.files = [good]
    ctrl.maxFilesValue = 1
    const input = element.querySelector("[data-ai-assistant-target='images']")
    Object.defineProperty(input, "files", {
      value: [file("a.png", "image/png", 4), file("b.png", "image/png", 4)],
      configurable: true
    })
    ctrl.pickImages()
    expect(ctrl.files).toEqual([good])
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toContain("at most")
  })

  it("rejects oversized files and empty accept still allows any type", async () => {
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.maxBytesValue = 2
    ctrl.files = []
    const input = element.querySelector("[data-ai-assistant-target='images']")
    Object.defineProperty(input, "files", { value: [file("big.png", "image/png", 8)], configurable: true })
    ctrl.pickImages()
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toContain("5MB")
    ctrl.acceptValue = ""
    ctrl.maxBytesValue = 100
    Object.defineProperty(input, "files", { value: [file("note.txt", "text/plain", 4)], configurable: true })
    ctrl.pickImages()
    expect(ctrl.files).toHaveLength(1)
  })

  it("rejects a selection whose files are each allowed but together over the total cap", async () => {
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.maxBytesValue = 10
    ctrl.maxTotalBytesValue = 12
    ctrl.files = []
    const input = element.querySelector("[data-ai-assistant-target='images']")
    Object.defineProperty(input, "files", {
      value: [file("a.png", "image/png", 8), file("b.png", "image/png", 8)],
      configurable: true
    })
    ctrl.pickImages()
    expect(ctrl.files).toEqual([])
    expect(element.querySelector("[data-ai-assistant-target='error']").textContent).toBe(
      "Attached images must total 20MB or less."
    )
  })

  it("picks files without preview or error targets and revokes without revokeObjectURL", async () => {
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ omitPreviews: true, omitError: true, value: "ok" })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")
    const input = element.querySelector("[data-ai-assistant-target='images']")
    Object.defineProperty(input, "files", { value: [file("shot.png", "image/png", 4)], configurable: true })
    expect(() => ctrl.pickImages()).not.toThrow()
    Object.defineProperty(input, "files", { value: null, configurable: true })
    expect(() => ctrl.pickImages()).not.toThrow()
    mockFetch(202)
    ctrl.send()
    await flush()

    const withPreview = await mountController("ai-assistant", Controller, panelHtml())
    const previewCtrl = controllerFor(withPreview.application, withPreview.element, "ai-assistant")
    const previewInput = withPreview.element.querySelector("[data-ai-assistant-target='images']")
    Object.defineProperty(previewInput, "files", { value: [file("shot.png", "image/png", 4)], configurable: true })
    previewCtrl.pickImages()
    URL.revokeObjectURL = undefined
    previewCtrl.pickImages()
    previewCtrl.disconnect()
  })

  it("attach and pickImages tolerate a missing file input", async () => {
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ omitImages: true })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")
    expect(() => ctrl.attach()).not.toThrow()
    expect(() => ctrl.pickImages()).not.toThrow()
    expect(() => ctrl.removeImage()).not.toThrow()
    expect(() => ctrl.removeImage({ preventDefault: vi.fn(), currentTarget: { dataset: { index: "nope" } } })).not.toThrow()
  })

  it("renders name-only chips when object URLs are unavailable", async () => {
    vi.stubGlobal("URL", {})
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    const input = element.querySelector("[data-ai-assistant-target='images']")
    Object.defineProperty(input, "files", { value: [file("shot.png", "image/png", 4)], configurable: true })
    ctrl.pickImages()
    expect(element.querySelector("[data-ai-assistant-target='previews'] img")).toBeNull()
    expect(element.querySelector("[data-ai-assistant-target='previews']").textContent).toContain("shot.png")
  })

  it("sends on Enter and allows Shift+Enter to pass through", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "enter" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.keydown({ key: "Enter", shiftKey: true, preventDefault: vi.fn() })
    expect(fetchMock).not.toHaveBeenCalled()
    const prevent = vi.fn()
    ctrl.keydown({ key: "Enter", shiftKey: false, preventDefault: prevent })
    await flush()
    expect(prevent).toHaveBeenCalled()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it("ignores keydown for keys other than Enter", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "a" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.keydown({ key: "a", shiftKey: false, preventDefault: vi.fn() })
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("send() without an event still posts", async () => {
    const fetchMock = mockFetch(202)
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml({ value: "go" }))
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.send()
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  // The panel is re-rendered offline by AiAssistant::Stream, so a token baked
  // into the element would belong to a throwaway session; the layout's meta
  // tag is the only one tied to the real one.
  it("reads the CSRF token from the meta tag", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "meta-csrf"
    document.head.appendChild(meta)

    try {
      const fetchMock = mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "x" }))
      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()
      expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("meta-csrf")
    } finally {
      meta.remove()
    }
  })

  it("sends an empty CSRF token when the meta tag is absent", async () => {
    const fetchMock = mockFetch(202)
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "x" }))
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("")
  })

  it("tolerates missing composer, thread, and button targets", async () => {
    mockFetch(202)
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({
        omitComposer: true,
        omitThread: true,
        omitButton: true,
        omitStop: true,
        omitRegenerate: true,
        omitJump: true,
        omitCopy: true,
        omitImages: true,
        omitPreviews: true,
        omitError: true
      })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.files = null
    expect(() => ctrl.send()).not.toThrow()
    expect(() => ctrl.stop()).not.toThrow()
    expect(() => ctrl.copy()).not.toThrow()
    expect(() => ctrl.disconnect()).not.toThrow()
    await tick()
  })

  it("does not throw when restoring the composer after the textarea is removed", async () => {
    let resolveFetch
    vi.stubGlobal("fetch", vi.fn().mockImplementation(() => new Promise((resolve) => { resolveFetch = resolve })))
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "keep" }))
    const textarea = element.querySelector("textarea")
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    textarea.remove()
    resolveFetch({ status: 422, ok: false, json: async () => ({}) })
    await flush()
    expect(element.querySelector("textarea")).toBeNull()
  })

  it("fills the composer from a prompt button", async () => {
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ prompt: "How do I create an entity?" })
    )
    await click(element.querySelector("[data-action='click->ai-assistant#usePrompt']"))
    expect(element.querySelector("textarea").value).toBe("How do I create an entity?")
  })

  it("grows the composer to fit its content and resets it after sending", async () => {
    mockFetch(202)
    const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "" }))
    const textarea = element.querySelector("textarea")
    Object.defineProperty(textarea, "scrollHeight", { value: 96, configurable: true })

    textarea.value = "line one\nline two\nline three"
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
    await tick()
    expect(textarea.style.height).toBe("96px")

    Object.defineProperty(textarea, "scrollHeight", { value: 44, configurable: true })
    await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
    await flush()
    expect(textarea.value).toBe("")
    expect(textarea.style.height).toBe("44px")
  })

  it("resize tolerates a missing composer", async () => {
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ omitComposer: true })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")

    expect(() => ctrl.resize()).not.toThrow()
  })

  it("prefers data-prompt over the visible label", async () => {
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ prompt: "Student", promptData: "Work on the Student entity." })
    )
    await click(element.querySelector("[data-action='click->ai-assistant#usePrompt']"))
    expect(element.querySelector("textarea").value).toBe("Work on the Student entity.")
  })

  it("does not fill the composer when the prompt button is empty", async () => {
    const { element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ value: "keep", prompt: "   " })
    )
    await click(element.querySelector("[data-action='click->ai-assistant#usePrompt']"))
    expect(element.querySelector("textarea").value).toBe("keep")
  })

  it("usePrompt does not throw without a composer or event", async () => {
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ omitComposer: true })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")
    expect(() => ctrl.usePrompt()).not.toThrow()
    expect(() => ctrl.usePrompt({ preventDefault: vi.fn(), currentTarget: null })).not.toThrow()
  })

  it("does not fill the composer when prompt text is missing", async () => {
    const { application, element } = await mountController(
      "ai-assistant",
      Controller,
      panelHtml({ value: "keep" })
    )
    const ctrl = controllerFor(application, element, "ai-assistant")
    ctrl.usePrompt({ preventDefault: vi.fn(), currentTarget: { textContent: "" } })
    expect(element.querySelector("textarea").value).toBe("keep")
  })

  describe("round cap and cooldown", () => {
    it("keeps the composer usable when the server sends no budget", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hi" }))

      expect(element.querySelector("[data-ai-assistant-target='sendButton']").disabled).toBe(false)
      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(fetchMock).toHaveBeenCalledTimes(1)
      expect(hintState(element)).toEqual({ text: "", hidden: true })
    })

    it("stays quiet while the cap is far away", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 12, turnsWarningAt: 5 })
      )
      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(hintState(element)).toEqual({ text: "", hidden: true })
    })

    it("counts down and warns once the thread nears the cap", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 3, turnsWarningAt: 5 })
      )
      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(hintState(element)).toEqual({ text: "2 messages left in this chat.", hidden: false })
    })

    it("locks the composer on the turn that spends the last round", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 1 })
      )
      const sendButton = element.querySelector("[data-ai-assistant-target='sendButton']")
      await click(sendButton)
      await flush()

      expect(hintState(element)).toEqual({
        text: "This chat has reached its limit. Start a new chat to continue.",
        hidden: false
      })
      expect(sendButton.disabled).toBe(true)
      expect(element.querySelector("textarea").disabled).toBe(true)
    })

    it("arrives disabled when the thread is already spent", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 0 })
      )
      const sendButton = element.querySelector("[data-ai-assistant-target='sendButton']")

      expect(sendButton.disabled).toBe(true)
      expect(element.querySelector("textarea").disabled).toBe(true)

      await click(sendButton)
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    // A rejected turn was never charged server-side, so the budget must hold.
    it("does not spend a round when the send fails", async () => {
      mockFetch(429, { json: { errors: [ "Too many requests." ] } })
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 2, turnsWarningAt: 5 })
      )
      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(hintState(element)).toEqual({ text: "", hidden: true })
      expect(element.querySelector("[data-ai-assistant-target='error']").textContent)
        .toBe("Too many requests.")
    })

    it("tolerates a panel rendered without the hint slot", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 1, omitTurnsHint: true })
      )

      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(element.querySelector("[data-ai-assistant-target='sendButton']").disabled).toBe(true)
    })

    // The reply landing is what releases the busy flag, so the cooldown is the
    // only thing left holding the next send back.
    async function replyArrives(element) {
      element.querySelector("[data-ai-assistant-target='thread']")
        .insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
      await tick()
    }

    it("swallows a second send inside the cooldown window", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ cooldownMs: 1200 })
      )
      const textarea = element.querySelector("textarea")
      const sendButton = element.querySelector("[data-ai-assistant-target='sendButton']")

      textarea.value = "first"
      await click(sendButton)
      await flush()
      await replyArrives(element)
      textarea.value = "second"
      await click(sendButton)
      await flush()

      expect(fetchMock).toHaveBeenCalledTimes(1)
      expect(textarea.value).toBe("second")
    })

    it("accepts the next send once the cooldown has elapsed", async () => {
      const fetchMock = mockFetch(202)
      const now = Date.now()
      const clock = vi.spyOn(Date, "now").mockReturnValue(now)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ cooldownMs: 1200 })
      )
      const textarea = element.querySelector("textarea")
      const sendButton = element.querySelector("[data-ai-assistant-target='sendButton']")

      textarea.value = "first"
      await click(sendButton)
      await flush()
      await replyArrives(element)
      clock.mockReturnValue(now + 1200)
      textarea.value = "second"
      await click(sendButton)
      await flush()

      expect(fetchMock).toHaveBeenCalledTimes(2)
      expect(textarea.value).toBe("")
    })
  })

  // The chat list owns the write, but below xl it is collapsed behind a
  // disclosure above the transcript — so "start a new chat" is only actionable
  // if the control is offered where the advice is given.
  describe("the escape hatch from a spent thread", () => {
    const newChatIn = (element) => element.querySelector("[data-ai-assistant-target='newChatButton']")

    it("stays out of the way while rounds remain", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ turnsRemaining: 3 }))

      expect(newChatIn(element).classList.contains("hidden")).toBe(true)
    })

    it("appears on the turn that spends the last round", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 1 })
      )

      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(newChatIn(element).classList.contains("hidden")).toBe(false)
    })

    // The list is not an ancestor of the composer, so the request travels as
    // an event it binds to on window.
    it("asks the chat list for a new chat rather than writing one itself", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ turnsRemaining: 0 }))
      const heard = vi.fn()
      window.addEventListener("ai-assistant:newChat", heard)

      try {
        await click(newChatIn(element))

        expect(heard).toHaveBeenCalledOnce()
        expect(fetchMock).not.toHaveBeenCalled()
      } finally {
        window.removeEventListener("ai-assistant:newChat", heard)
      }
    })

    it("dispatches without an event to suppress", async () => {
      mockFetch(202)
      const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
      const ctrl = controllerFor(application, element, "ai-assistant")
      const heard = vi.fn()
      window.addEventListener("ai-assistant:newChat", heard)

      try {
        ctrl.newChat()

        expect(heard).toHaveBeenCalledOnce()
      } finally {
        window.removeEventListener("ai-assistant:newChat", heard)
      }
    })

    it("tolerates a panel rendered without the control", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ turnsRemaining: 0, omitNewChat: true })
      )

      expect(newChatIn(element)).toBeNull()
      expect(element.querySelector("textarea").disabled).toBe(true)
    })
  })

  // Routine validation and refusals must not cut across a reply that is still
  // arriving; a connection that has gone is the one failure that cannot wait.
  describe("how loudly the composer's errors are announced", () => {
    const liveness = (element) => errorIn(element).getAttribute("aria-live")

    it("keeps attachment validation polite", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      const input = element.querySelector("input[type='file']")

      Object.defineProperty(input, "files", { value: [ file("a.exe", "application/x-msdownload", 10) ], configurable: true })
      input.dispatchEvent(new Event("change", { bubbles: true }))
      await tick()

      expect(errorIn(element).textContent).toBe("That image type is not allowed.")
      expect(liveness(element)).toBe("polite")
    })

    it("keeps a refused send polite too", async () => {
      mockFetch(422, { json: { errors: [ "Enter a message." ] } })
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hi" }))

      await click(sendIn(element))
      await flush()

      expect(liveness(element)).toBe("polite")
    })

    // The one failure that interrupts lives with the watchdog, in "the stream
    // watchdog" below, where the fake clock is already wound.
  })

  describe("conversation identity", () => {
    it("names the conversation the turn belongs to in the FormData", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", conversationId: "conv-42" })
      )

      await click(sendIn(element))
      await flush()

      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("conv-42")
    })

    // Sending is not the end of the conversation, so the caret goes back where
    // the next message gets written.
    it("returns focus to the composer once the turn is accepted", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hi" }))
      const composer = composerIn(element)
      sendIn(element).focus()

      await click(sendIn(element))
      await flush()

      expect(document.activeElement).toBe(composer)
    })

    it("sends attachments from a panel that has no composer to focus", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ omitComposer: true })
      )
      const ctrl = controllerFor(application, element, "ai-assistant")
      ctrl.files = [file("shot.png", "image/png", 4)]

      ctrl.send()
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      expect(fetchMock.mock.calls[0][1].body.get("body")).toBe("")
    })
  })

  describe("the composer placeholder", () => {
    it("explains the lock instead of still inviting a message", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 1 })
      )
      const composer = composerIn(element)
      expect(composer.placeholder).toBe(IDLE_PLACEHOLDER)

      await click(sendIn(element))
      await flush()

      expect(composer.disabled).toBe(true)
      expect(composer.placeholder).toBe(EXHAUSTED_LABEL)
    })

    it("keeps the invitation while rounds remain", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", turnsRemaining: 4 })
      )

      await click(sendIn(element))
      await flush()

      expect(composerIn(element).disabled).toBe(false)
      expect(composerIn(element).placeholder).toBe(IDLE_PLACEHOLDER)
    })
  })

  describe("the regenerate button", () => {
    it("is held shut for the length of a running turn", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hi" }))
      expect(regenerateIn(element).disabled).toBe(false)

      await click(sendIn(element))
      await flush()
      expect(regenerateIn(element).disabled).toBe(true)

      threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
      await tick()

      expect(regenerateIn(element).disabled).toBe(false)
    })

    it("arrives shut when the thread is already spent", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ turnsRemaining: 0 }))

      expect(regenerateIn(element).disabled).toBe(true)
    })
  })

  describe("regenerate", () => {
    it("replays the last turn as JSON naming the conversation", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ conversationId: "conv-7" })
      )
      const ctrl = controllerFor(application, element, "ai-assistant")
      const composer = composerIn(element)
      errorIn(element).textContent = "an older failure"
      sendIn(element).focus()

      await click(regenerateIn(element))
      await flush()

      const [url, options] = fetchMock.mock.calls[0]
      expect(url).toBe("/messages/regenerate")
      expect(options.method).toBe("POST")
      expect(options.headers["Content-Type"]).toBe("application/json")
      expect(JSON.parse(options.body)).toEqual({ conversation_id: "conv-7" })
      expect(ctrl.busy).toBe(true)
      expect(errorIn(element).textContent).toBe("")
      expect(errorIn(element).classList.contains("hidden")).toBe(true)
      expect(document.activeElement).toBe(composer)
    })

    it("regenerate() without an event still posts", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
      const ctrl = controllerFor(application, element, "ai-assistant")

      ctrl.regenerate()
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
    })

    it("does nothing without a regenerate endpoint", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ regenerateUrl: "" }))

      await click(regenerateIn(element))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    // The same round budget and the same reply job, so the same three guards.
    it("refuses while a turn is already running", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ value: "hi" }))

      await click(sendIn(element))
      await flush()
      await click(regenerateIn(element))
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      expect(fetchMock.mock.calls[0][0]).toBe("/messages")
    })

    it("refuses inside the cooldown window", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", cooldownMs: 1200 })
      )

      await click(sendIn(element))
      await flush()
      threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
      await tick()
      await click(regenerateIn(element))
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
    })

    it("refuses once the rounds are spent", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ turnsRemaining: 0 })
      )
      const ctrl = controllerFor(application, element, "ai-assistant")

      ctrl.regenerate()
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("reports a refused regenerate and frees the panel", async () => {
      mockFetch(403)
      const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
      const ctrl = controllerFor(application, element, "ai-assistant")

      await click(regenerateIn(element))
      await flush()

      expect(ctrl.busy).toBe(false)
      expect(errorIn(element).textContent).toBe("Could not regenerate the reply.")
      expect(errorIn(element).classList.contains("hidden")).toBe(false)
    })

    it("reports a regenerate that never reached the server", async () => {
      mockFetch(0, { reject: true })
      const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
      const ctrl = controllerFor(application, element, "ai-assistant")

      await click(regenerateIn(element))
      await flush()

      expect(ctrl.busy).toBe(false)
      expect(errorIn(element).textContent).toBe("Could not regenerate the reply.")
    })
  })

  describe("stop failures", () => {
    it("names the conversation in the stop body", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ conversationId: "conv-9" })
      )

      await click(element.querySelector("[data-ai-assistant-target='stopButton']"))
      await flush()

      const options = fetchMock.mock.calls[0][1]
      expect(options.headers["Content-Type"]).toBe("application/json")
      expect(JSON.parse(options.body)).toEqual({ conversation_id: "conv-9" })
    })

    // A refused stop leaves the turn running, so saying nothing would read as
    // "stopped" while the reply keeps arriving.
    it("says so when the server refuses to stop the turn", async () => {
      mockFetch(409)
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await click(element.querySelector("[data-ai-assistant-target='stopButton']"))
      await flush()

      expect(errorIn(element).textContent).toBe("Could not stop the reply.")
      expect(errorIn(element).classList.contains("hidden")).toBe(false)
    })

    it("says so when the stop request never reaches the server", async () => {
      mockFetch(0, { reject: true })
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await click(element.querySelector("[data-ai-assistant-target='stopButton']"))
      await flush()

      expect(errorIn(element).textContent).toBe("Could not stop the reply.")
    })
  })

  // A turn can be started by dictation, by another tab, or be in flight when
  // the page is reloaded, so the composer's state has to come from the
  // server's flag rather than from an assumption that it opens idle.
  describe("the server's running flag", () => {
    const stopIn = (element) => element.querySelector("[data-ai-assistant-target='stopButton']")
    const sendIn = (element) => element.querySelector("[data-ai-assistant-target='sendButton']")

    it("opens showing Stop when a turn is already running", async () => {
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "true" }))

      expect(stopIn(element).classList.contains("hidden")).toBe(false)
      expect(sendIn(element).classList.contains("hidden")).toBe(true)
    })

    it("opens idle when the flag says nothing is running", async () => {
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "false" }))

      expect(stopIn(element).classList.contains("hidden")).toBe(true)
      expect(sendIn(element).classList.contains("hidden")).toBe(false)
    })

    it("reads the flag by id when it carries no Stimulus target", async () => {
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ running: "true", runningFlagUntargeted: true })
      )

      expect(stopIn(element).classList.contains("hidden")).toBe(false)
    })

    it("opens idle when there is no flag at all", async () => {
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      expect(stopIn(element).classList.contains("hidden")).toBe(true)
    })
  })

  describe("acknowledging Stop", () => {
    const stopIn = (element) => element.querySelector("[data-ai-assistant-target='stopButton']")

    it("disables the button and renames it while the request is in flight", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "true" }))

      await click(stopIn(element))

      expect(stopIn(element).disabled).toBe(true)
      expect(stopIn(element).getAttribute("aria-label")).toBe("Stopping…")
      expect(stopIn(element).title).toBe("Stopping…")
    })

    it("ignores a second press while the first stop is still in flight", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "true" }))

      await click(stopIn(element))
      await click(stopIn(element))
      await flush()

      expect(fetchMock).toHaveBeenCalledTimes(1)
    })

    // Pressing Stop again is the only thing left to try, so a refusal has to
    // hand the button back rather than leave it renamed and disabled.
    it("hands the button back when the server refuses to stop", async () => {
      mockFetch(409)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "true" }))

      await click(stopIn(element))
      await flush()

      expect(stopIn(element).disabled).toBe(false)
      expect(stopIn(element).getAttribute("aria-label")).toBe("Stop")
    })

    it("hands the button back when the stop request never arrives", async () => {
      mockFetch(0, { reject: true })
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "true" }))

      await click(stopIn(element))
      await flush()

      expect(stopIn(element).disabled).toBe(false)
    })

    it("clears the stopping state once the turn actually ends", async () => {
      mockFetch(202)
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ running: "true" }))

      await click(stopIn(element))
      await flush()

      const flag = element.querySelector("#ai_assistant_running")
      flag.remove()
      const replacement = document.createElement("div")
      replacement.id = "ai_assistant_running"
      replacement.setAttribute("data-running", "false")
      element.appendChild(replacement)
      await tick()

      expect(stopIn(element).classList.contains("hidden")).toBe(true)
      expect(stopIn(element).disabled).toBe(false)
    })
  })

  describe("the stream watchdog", () => {
    beforeEach(() => {
      vi.useFakeTimers({ shouldAdvanceTime: true })
    })

    afterEach(() => {
      vi.useRealTimers()
    })

    async function runningPanel(overrides = {}) {
      mockFetch(202)
      const mounted = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ value: "hi", watchdogMs: 1000, ...overrides })
      )
      const ctrl = controllerFor(mounted.application, mounted.element, "ai-assistant")
      await click(sendIn(mounted.element))
      await flush()
      return { ...mounted, ctrl }
    }

    // A dropped socket would otherwise leave the composer showing Stop for
    // ever, with no way back short of a reload.
    it("gives up on a silent stream and blames the connection", async () => {
      const { ctrl, element } = await runningPanel()
      expect(ctrl.busy).toBe(true)
      expect(ctrl.watchdogTimer).toBeTruthy()

      await vi.advanceTimersByTimeAsync(1100)

      expect(ctrl.busy).toBe(false)
      expect(ctrl.watchdogTimer).toBeNull()
      expect(errorIn(element).textContent).toBe(CONNECTION_LOST_LABEL)
      // The one composer failure worth cutting across a reply still arriving.
      expect(errorIn(element).getAttribute("aria-live")).toBe("assertive")
      expect(sendIn(element).classList.contains("hidden")).toBe(false)
      expect(element.querySelector("[data-ai-assistant-target='stopButton']").classList.contains("hidden")).toBe(true)
    })

    // Any traffic at all means the stream is alive, so the turn gets its full
    // patience back rather than counting down from the send.
    it("hands the turn its patience back on every scrap of traffic", async () => {
      const { ctrl, element } = await runningPanel()

      await vi.advanceTimersByTimeAsync(700)
      element.appendChild(document.createElement("span"))
      await tick()
      await vi.advanceTimersByTimeAsync(700)

      expect(ctrl.busy).toBe(true)
      expect(errorIn(element).textContent).toBe("")

      await vi.advanceTimersByTimeAsync(400)

      expect(ctrl.busy).toBe(false)
      expect(errorIn(element).textContent).toBe(CONNECTION_LOST_LABEL)
    })

    it("stands down entirely when the panel declares no budget", async () => {
      const { ctrl, element } = await runningPanel({ watchdogMs: 0 })

      expect(ctrl.watchdogTimer).toBeNull()
      await vi.advanceTimersByTimeAsync(200_000)

      expect(ctrl.busy).toBe(true)
      expect(errorIn(element).textContent).toBe("")
    })

    it("is dropped when the panel goes away mid-turn", async () => {
      const { ctrl, element } = await runningPanel()
      expect(ctrl.watchdogTimer).toBeTruthy()

      ctrl.disconnect()

      expect(ctrl.watchdogTimer).toBeNull()
      await vi.advanceTimersByTimeAsync(1100)
      expect(errorIn(element).textContent).toBe("")
    })

    // A reply that lands on the deadline must not be papered over with a
    // lost-connection notice.
    it("stays quiet when the turn has already finished", async () => {
      const { ctrl, element } = await runningPanel()
      ctrl.busy = false

      await vi.advanceTimersByTimeAsync(1100)

      expect(ctrl.watchdogTimer).toBeNull()
      expect(errorIn(element).textContent).toBe("")
    })
  })

  describe("scroll pinning", () => {
    async function panel(overrides = {}, geometry = {}) {
      mockFetch(202)
      const mounted = await mountController("ai-assistant", Controller, panelHtml(overrides))
      const ctrl = controllerFor(mounted.application, mounted.element, "ai-assistant")
      if (!overrides.omitThread) sizeThread(mounted.element, geometry)
      return { ...mounted, ctrl }
    }

    const scroll = (element) => {
      threadIn(element).dispatchEvent(new Event("scroll", { bubbles: true }))
      return tick()
    }

    // PINNED_SLACK_PX: a reader this close to the foot still counts as reading
    // the latest, so a reply is allowed to move the viewport.
    it("counts a reader inside the slack as still reading the latest", async () => {
      const { ctrl, element } = await panel({}, { scrollHeight: 1000, clientHeight: 400, scrollTop: 520 })
      ctrl.pinned = false
      jumpIn(element).classList.remove("hidden")

      await scroll(element)

      expect(ctrl.pinned).toBe(true)
      expect(jumpVisible(element)).toBe(false)
    })

    // The button starts hidden, so scrolling away has to reveal it — otherwise
    // the only way back to the foot of a long thread is a manual scroll.
    it("counts a reader one pixel past the slack as scrolled away", async () => {
      const { ctrl, element } = await panel({}, { scrollHeight: 1000, clientHeight: 400, scrollTop: 519 })
      expect(jumpVisible(element)).toBe(false)

      await scroll(element)

      expect(ctrl.pinned).toBe(false)
      expect(jumpVisible(element)).toBe(true)
    })

    it("scrolls an arriving reply into view while pinned", async () => {
      const { ctrl, element } = await panel({}, { scrollTop: 0 })
      ctrl.pinned = true

      threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
      await tick()

      expect(threadIn(element).scrollTop).toBe(1000)
      expect(jumpVisible(element)).toBe(false)
    })

    it("offers the jump button instead of yanking the viewport", async () => {
      const { ctrl, element } = await panel()
      ctrl.pinned = false

      threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
      await tick()

      expect(threadIn(element).scrollTop).toBe(600)
      expect(jumpVisible(element)).toBe(true)
    })

    it("re-pins, scrolls, and puts the button away when the reader jumps", async () => {
      const { ctrl, element } = await panel({}, { scrollTop: 100 })
      ctrl.pinned = false
      jumpIn(element).classList.remove("hidden")

      await click(jumpIn(element))

      expect(ctrl.pinned).toBe(true)
      expect(threadIn(element).scrollTop).toBe(1000)
      expect(jumpVisible(element)).toBe(false)
    })

    it("jumpToLatest() without an event still scrolls", async () => {
      const { ctrl, element } = await panel({}, { scrollTop: 100 })

      ctrl.jumpToLatest()

      expect(threadIn(element).scrollTop).toBe(1000)
    })

    // Mention rows and attachment previews are rebuilt inside this element
    // too, and neither is a reason to move the transcript.
    it("ignores a mutation outside the transcript", async () => {
      const { ctrl, element } = await panel()
      ctrl.pinned = true

      element.querySelector("[data-ai-assistant-target='previews']").appendChild(document.createElement("li"))
      await tick()

      expect(threadIn(element).scrollTop).toBe(600)
      expect(jumpVisible(element)).toBe(false)
    })

    it("has nothing to pin or reveal without a transcript", async () => {
      const { ctrl, element } = await panel({ omitThread: true })
      ctrl.pinned = false

      ctrl.threadScrolled()
      element.appendChild(document.createElement("span"))
      await tick()

      expect(ctrl.pinned).toBe(true)
      expect(jumpVisible(element)).toBe(false)
      expect(() => ctrl.jumpToLatest()).not.toThrow()
    })

    it("tolerates a panel rendered without the jump button", async () => {
      const { ctrl, element } = await panel({ omitJump: true })
      ctrl.pinned = false

      threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
      await tick()

      expect(jumpIn(element)).toBeNull()
      expect(() => ctrl.jumpToLatest()).not.toThrow()
      expect(() => ctrl.threadScrolled()).not.toThrow()
    })

    // `scroll` is coalesced to roughly one event a frame, so during a fast
    // stream every mutation inside that window still reads `pinned` as true
    // and snaps the viewport back down. The gesture arrives first.
    describe("taking the viewport back mid-stream", () => {
      const wheel = (element, deltaY) => {
        const event = new Event("wheel", { bubbles: true, cancelable: true })
        event.deltaY = deltaY
        threadIn(element).dispatchEvent(event)
        return tick()
      }

      const touch = (element, type, clientY) => {
        const event = new Event(type, { bubbles: true, cancelable: true })
        if (clientY != null) event.touches = [ { clientY } ]
        threadIn(element).dispatchEvent(event)
        return tick()
      }

      it("unpins on a wheel back through the thread, before any scroll lands", async () => {
        const { ctrl, element } = await panel()
        ctrl.pinned = true

        await wheel(element, -120)

        expect(ctrl.pinned).toBe(false)
        expect(jumpVisible(element)).toBe(true)
      })

      it("stays pinned when the wheel is going the same way as the reply", async () => {
        const { ctrl, element } = await panel()
        ctrl.pinned = true

        await wheel(element, 120)

        expect(ctrl.pinned).toBe(true)
        expect(jumpVisible(element)).toBe(false)
      })

      it("leaves an arriving reply where the reader put the viewport", async () => {
        const { ctrl, element } = await panel()
        ctrl.pinned = true
        await wheel(element, -120)

        threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ role: "assistant", body: "Sure" }))
        await tick()

        expect(threadIn(element).scrollTop).toBe(600)
      })

      it("unpins on a finger dragged back down the screen", async () => {
        const { ctrl, element } = await panel()
        ctrl.pinned = true

        await touch(element, "touchstart", 200)
        expect(ctrl.pinned).toBe(true)

        await touch(element, "touchmove", 260)

        expect(ctrl.pinned).toBe(false)
      })

      // Measured against where this gesture started, not where the last one
      // ended, or a fresh tap lower down the screen would read as a drag.
      it("measures each drag from its own start", async () => {
        const { ctrl, element } = await panel()
        await touch(element, "touchstart", 400)
        await touch(element, "touchmove", 200)
        ctrl.pinned = true

        await touch(element, "touchstart", 300)

        expect(ctrl.pinned).toBe(true)
      })

      it("stays pinned on a finger dragged up toward the latest", async () => {
        const { ctrl, element } = await panel()
        ctrl.pinned = true
        await touch(element, "touchstart", 400)

        await touch(element, "touchmove", 340)

        expect(ctrl.pinned).toBe(true)
      })

      it("ignores a gesture that carries neither a delta nor a touch", async () => {
        const { ctrl, element } = await panel()
        ctrl.pinned = true

        await touch(element, "touchmove", null)

        expect(ctrl.pinned).toBe(true)
      })

      // A scrollbar drag and a keyboard scroll produce no gesture event, so
      // the scroll handler still settles the state both ways.
      it("re-pins once the reader gets back to the foot", async () => {
        const { ctrl, element } = await panel({}, { scrollHeight: 1000, clientHeight: 400, scrollTop: 1000 })
        ctrl.pinned = true
        await wheel(element, -120)
        expect(ctrl.pinned).toBe(false)

        await scroll(element)

        expect(ctrl.pinned).toBe(true)
        expect(jumpVisible(element)).toBe(false)
      })
    })
  })

  describe("@ mentions", () => {
    it("opens the menu on @ with this tenant's artifacts and their kind", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@")

      expect(fetchMock).toHaveBeenCalledWith("/messages/mentions", { headers: { Accept: "application/json" } })
      expect(menuOpen(element)).toBe(true)
      expect(optionLabels(element)).toEqual(["InvoicesEntity", "Purchase OrdersEntity", "Issue invoiceFlowchart"])
      expect(element.querySelector("textarea").getAttribute("aria-expanded")).toBe("true")
      expect(element.querySelector("textarea").getAttribute("aria-activedescendant")).toBe("ai-assistant-mention-0")
      expect(selectedIn(element).textContent).toBe("InvoicesEntity")
    })

    // The listbox owns the options, not the `li` wrappers the markup needs.
    it("hides the row wrappers from the listbox", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@")

      const wrappers = Array.from(element.querySelectorAll("[data-ai-assistant-target='mentionList'] > li"))
      expect(wrappers).toHaveLength(3)
      expect(wrappers.map((item) => item.getAttribute("role"))).toEqual(["presentation", "presentation", "presentation"])
    })

    it("filters on the typed name or label, across words", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@invo")
      expect(optionLabels(element)).toEqual(["InvoicesEntity", "Issue invoiceFlowchart"])

      await type(element, "@purchase or")
      expect(optionLabels(element)).toEqual(["Purchase OrdersEntity"])
    })

    it("caps the menu so it cannot cover the thread", async () => {
      const many = Array.from({ length: 12 }, (_row, index) => ({
        kind: "entity",
        name: `Entity ${index}`,
        label: `Entity ${index}`
      }))
      mockMentions(many)
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@")

      expect(optionsIn(element).length).toBe(8)
    })

    // The `ul` is presentational, so a row with no role of its own is not in
    // the listbox at all and never reaches a screen reader.
    it("says so when nothing matches, as a row assistive tech can reach", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@zzz")

      expect(menuOpen(element)).toBe(true)
      expect(menuIn(element).textContent).toBe("No match")

      const empty = optionsIn(element)[0]
      expect(optionsIn(element)).toHaveLength(1)
      expect(empty.getAttribute("aria-disabled")).toBe("true")
      expect(empty.getAttribute("aria-selected")).toBe("false")
      expect(empty.id).toBe("ai-assistant-mention-empty")
      expect(element.querySelector("textarea").getAttribute("aria-activedescendant"))
        .toBe("ai-assistant-mention-empty")
    })

    it("completes the highlighted row on Enter instead of sending", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "Update @purch soon", 13)
      expect(optionLabels(element)).toEqual(["Purchase OrdersEntity"])

      const { defaultPrevented } = pressKey(element, "Enter")
      await flush()

      expect(defaultPrevented).toBe(true)
      expect(element.querySelector("textarea").value).toBe("Update @Purchase Order  soon")
      expect(element.querySelector("textarea").selectionStart).toBe(23)
      expect(menuOpen(element)).toBe(false)
      expect(fetchMock.mock.calls.every(([url]) => url === "/messages/mentions")).toBe(true)
    })

    // Enter at an IME candidate list commits the candidate. Treating it as a
    // completion or a send would post half-typed pinyin.
    it("leaves Enter to the IME while a candidate is being composed", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@inv")
      const { defaultPrevented } = pressKey(element, "Enter", { isComposing: true })
      await flush()

      expect(defaultPrevented).toBe(false)
      expect(element.querySelector("textarea").value).toBe("@inv")
      expect(fetchMock.mock.calls.every(([url]) => url === "/messages/mentions")).toBe(true)
    })

    it("does not open the menu on the pinyin an IME is still composing", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      const composer = element.querySelector("textarea")

      composer.value = "@inv"
      composer.setSelectionRange(4, 4)
      const input = new Event("input", { bubbles: true })
      input.isComposing = true
      composer.dispatchEvent(input)
      await flush()
      expect(menuOpen(element)).toBe(false)

      composer.dispatchEvent(new Event("compositionend", { bubbles: true }))
      await flush()
      await flush()
      expect(menuOpen(element)).toBe(true)
    })

    it("leaves Shift+Enter as a line break and Shift+Tab as focus", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@inv")
      expect(pressKey(element, "Enter", { shiftKey: true }).defaultPrevented).toBe(false)
      expect(element.querySelector("textarea").value).toBe("@inv")

      expect(pressKey(element, "Tab", { shiftKey: true }).defaultPrevented).toBe(false)
      expect(element.querySelector("textarea").value).toBe("@inv")
    })

    it("completes on Tab too", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@invoi")
      pressKey(element, "Tab")
      await flush()

      expect(element.querySelector("textarea").value).toBe("@Invoice ")
    })

    it("moves the highlight with the arrow keys and wraps around", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "@")

      pressKey(element, "ArrowDown")
      expect(selectedIn(element).textContent).toBe("Purchase OrdersEntity")
      expect(element.querySelector("textarea").getAttribute("aria-activedescendant")).toBe("ai-assistant-mention-1")

      pressKey(element, "ArrowUp")
      pressKey(element, "ArrowUp")
      expect(selectedIn(element).textContent).toBe("Issue invoiceFlowchart")

      pressKey(element, "ArrowDown")
      expect(selectedIn(element).textContent).toBe("InvoicesEntity")
    })

    it("closes on Escape and on blur, leaving the text alone", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@inv")
      expect(pressKey(element, "Escape").defaultPrevented).toBe(true)
      expect(menuOpen(element)).toBe(false)
      expect(element.querySelector("textarea").value).toBe("@inv")
      expect(element.querySelector("textarea").getAttribute("aria-expanded")).toBe("false")

      await type(element, "@inv")
      expect(menuOpen(element)).toBe(true)
      element.querySelector("textarea").dispatchEvent(new Event("blur", { bubbles: true }))
      await tick()
      expect(menuOpen(element)).toBe(true)
      await new Promise((resolve) => setTimeout(resolve, 200))
      expect(menuOpen(element)).toBe(false)
    })

    it("still completes a row whose click arrives after the composer has blurred", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "@inv")

      element.querySelector("textarea").dispatchEvent(new Event("blur", { bubbles: true }))
      const option = optionsIn(element)[0]
      await click(option)

      expect(element.querySelector("textarea").value).toBe("@Invoice ")
      expect(menuOpen(element)).toBe(false)
    })

    it("sends on Enter when the menu has nothing to complete", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@zzz")
      pressKey(element, "Enter")
      await flush()

      expect(fetchMock.mock.calls.some(([url]) => url === "/messages")).toBe(true)
    })

    it("completes the clicked row without stealing focus from the composer", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "Bridge @iss to it", 11)

      const option = optionsIn(element)[0]
      const mousedown = new Event("mousedown", { bubbles: true, cancelable: true })
      option.dispatchEvent(mousedown)
      await click(option)

      expect(mousedown.defaultPrevented).toBe(true)
      expect(element.querySelector("textarea").value).toBe("Bridge @Issue invoice  to it")
      expect(menuOpen(element)).toBe(false)
    })

    it("drops a pending blur close when the panel is disconnected", async () => {
      mockMentions()
      const first = await mountController("ai-assistant", Controller, panelHtml())
      await type(first.element, "@")
      first.element.querySelector("textarea").dispatchEvent(new Event("blur", { bubbles: true }))

      await mountController("ai-assistant", Controller, panelHtml())
      await new Promise((resolve) => setTimeout(resolve, 200))
    })

    it("cancels a pending blur close when the pointer lands on the menu", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "@")

      element.querySelector("textarea").dispatchEvent(new Event("blur", { bubbles: true }))
      const list = element.querySelector("[data-ai-assistant-target='mentionList']")
      list.dispatchEvent(new Event("pointerdown", { bubbles: true, cancelable: true }))
      await new Promise((resolve) => setTimeout(resolve, 200))

      expect(menuOpen(element)).toBe(true)
    })

    // With more matches than fit, the list is grabbed by its scrollbar — which
    // is part of the menu but not part of any row, so a per-row suppression
    // let the composer blur and the menu vanish mid-drag.
    it("keeps the menu open when the grab lands on its scrollbar or padding", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "@")

      const list = element.querySelector("[data-ai-assistant-target='mentionList']")
      const mousedown = new Event("mousedown", { bubbles: true, cancelable: true })
      list.dispatchEvent(mousedown)

      expect(mousedown.defaultPrevented).toBe(true)
      expect(menuOpen(element)).toBe(true)

      const pointerdown = new Event("pointerdown", { bubbles: true, cancelable: true })
      list.dispatchEvent(pointerdown)
      expect(pointerdown.defaultPrevented).toBe(false)
      expect(menuOpen(element)).toBe(true)
    })

    it("falls back to the highlighted row when the click carries no index", async () => {
      mockMentions()
      const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
      const ctrl = controllerFor(application, element, "ai-assistant")
      await type(element, "@")

      ctrl.pickMention()

      expect(element.querySelector("textarea").value).toBe("@Invoice ")
    })

    it("ignores a completion with no row to insert", async () => {
      mockMentions()
      const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
      const ctrl = controllerFor(application, element, "ai-assistant")
      await type(element, "@")

      ctrl.pickMention({ preventDefault() {}, currentTarget: { dataset: { index: "9" } } })

      expect(element.querySelector("textarea").value).toBe("@")
    })

    it("leaves an email address alone, since its @ does not start a word", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "mail ada@example.com")

      expect(menuOpen(element)).toBe(false)
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("gives up once the text stops looking like a name", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@Invoice needs a due date")
      expect(menuOpen(element)).toBe(false)

      await type(element, `@${"x".repeat(41)}`)
      expect(menuOpen(element)).toBe(false)

      await type(element, "@inv\nmore", 9)
      expect(menuOpen(element)).toBe(false)
    })

    it("caches the list briefly, then refreshes so a new entity shows up", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      const now = vi.spyOn(Date, "now")
      now.mockReturnValue(1_000)

      await type(element, "@inv")
      await type(element, "")
      await type(element, "@pur")
      expect(fetchMock).toHaveBeenCalledTimes(1)

      now.mockReturnValue(1_000 + 15_001)
      await type(element, "")
      await type(element, "@inv")
      expect(fetchMock).toHaveBeenCalledTimes(2)
    })

    it("keeps quiet when the list cannot be loaded", async () => {
      const failing = vi.fn().mockResolvedValue({ status: 403, ok: false, json: async () => ({}) })
      vi.stubGlobal("fetch", failing)
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@inv")

      expect(menuIn(element).textContent).toBe("No match")
    })

    // Each case needs its own panel: the list is cached per controller, so a
    // second attempt on the same one would never reach the network.
    it("survives a rejected request and a body that is not JSON", async () => {
      const responses = [
        vi.fn().mockRejectedValue(new Error("offline")),
        vi.fn().mockResolvedValue({ status: 200, ok: true, json: async () => { throw new Error("not json") } }),
        vi.fn().mockResolvedValue({ status: 200, ok: true, json: async () => ({}) })
      ]

      for (const stub of responses) {
        vi.stubGlobal("fetch", stub)
        const { element } = await mountController("ai-assistant", Controller, panelHtml())
        await type(element, "@inv")

        expect(stub).toHaveBeenCalledOnce()
        expect(menuIn(element).textContent).toBe("No match")
      }
    })

    it("does nothing at all without an endpoint", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml({ mentionsUrl: "" }))

      await type(element, "@inv")

      expect(fetchMock).not.toHaveBeenCalled()
      expect(menuIn(element).textContent).toBe("No match")
    })

    it("stays inert when the panel has no menu or no composer", async () => {
      mockMentions()
      const bare = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({ omitMentionMenu: true, omitMentionList: true })
      )
      await type(bare.element, "@inv")
      expect(bare.element.querySelector("[role='option']")).toBeNull()

      const headless = await mountController("ai-assistant", Controller, panelHtml({ omitComposer: true }))
      const ctrl = controllerFor(headless.application, headless.element, "ai-assistant")
      ctrl.compose()
      ctrl.closeMentions()
      await flush()
      expect(menuOpen(headless.element)).toBe(false)
    })

    // The list arrives a moment after the keystroke, by which time the admin
    // may have typed past the mention.
    it("drops the menu when the mention is gone by the time the list lands", async () => {
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => ({
        status: 200,
        ok: true,
        json: async () => {
          const composer = element.querySelector("textarea")
          composer.value = "never mind"
          composer.setSelectionRange(10, 10)
          return { mentions: MENTIONS }
        }
      })))

      await type(element, "@inv")

      expect(menuOpen(element)).toBe(false)
      expect(optionsIn(element)).toEqual([])
    })

    it("ignores an unrelated key while the menu is open", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "@inv")

      expect(pressKey(element, "ArrowLeft").defaultPrevented).toBe(false)
      expect(menuOpen(element)).toBe(true)
    })

    it("has nothing to move through when only the empty row is showing", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      await type(element, "@zzz")

      pressKey(element, "ArrowDown")

      expect(menuIn(element).textContent).toBe("No match")
      expect(optionsIn(element).map((option) => option.id)).toEqual(["ai-assistant-mention-empty"])
    })

    // An artifact with no label still needs a row, and a kind the client has
    // no word for must not paint its raw key.
    it("falls back to the name, and to no badge at all", async () => {
      mockMentions([{ kind: "page", name: "Invoice detail", label: "" }])
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@inv")

      expect(optionLabels(element)).toEqual(["Invoice detail"])
    })

    // Arrow keys fire no input event, so the menu can outlive the mention.
    it("drops a stale menu instead of completing at the old caret", async () => {
      const fetchMock = mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      const composer = element.querySelector("textarea")

      await type(element, "@inv done")
      await type(element, "@inv done", 4)
      expect(menuOpen(element)).toBe(true)

      composer.setSelectionRange(9, 9) // ArrowRight past the mention
      pressKey(element, "Enter")
      await flush()

      expect(composer.value).toBe("")
      expect(menuOpen(element)).toBe(false)
      expect(fetchMock.mock.calls.some(([url]) => url === "/messages")).toBe(true)
    })

    it("drops a stale menu when the caret moves ahead of the @ altogether", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      const composer = element.querySelector("textarea")

      await type(element, "@inv")
      composer.setSelectionRange(0, 0) // ArrowLeft to the start of the line

      expect(pressKey(element, "ArrowDown").defaultPrevented).toBe(false)
      expect(menuOpen(element)).toBe(false)
      expect(composer.value).toBe("@inv")
    })

    it("closes the menu when the message is sent", async () => {
      mockMentions()
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@inv")
      await click(element.querySelector("[data-ai-assistant-target='sendButton']"))
      await flush()

      expect(menuOpen(element)).toBe(false)
      expect(optionsIn(element)).toEqual([])
    })

    it("remembers an empty list and a refusal, instead of asking on every keystroke", async () => {
      const empty = vi.fn().mockResolvedValue({ status: 200, ok: true, json: async () => ({ mentions: [] }) })
      vi.stubGlobal("fetch", empty)
      const { element } = await mountController("ai-assistant", Controller, panelHtml())

      await type(element, "@i")
      await type(element, "@in")
      expect(empty).toHaveBeenCalledTimes(1)

      const refused = vi.fn().mockResolvedValue({ status: 403, ok: false, json: async () => ({}) })
      vi.stubGlobal("fetch", refused)
      const fresh = await mountController("ai-assistant", Controller, panelHtml())
      await type(fresh.element, "@i")
      await type(fresh.element, "@in")
      expect(refused).toHaveBeenCalledTimes(1)
    })

    // Keystrokes outrun the round trip, and two responses could land out of
    // order and reinstate a list the second request had replaced.
    it("keeps one request in flight while the admin keeps typing", async () => {
      let release
      const pending = new Promise((resolve) => { release = resolve })
      const slow = vi.fn().mockImplementation(async () => {
        await pending
        return { status: 200, ok: true, json: async () => ({ mentions: MENTIONS }) }
      })
      vi.stubGlobal("fetch", slow)
      const { element } = await mountController("ai-assistant", Controller, panelHtml())
      const composer = element.querySelector("textarea")

      composer.value = "@i"
      composer.setSelectionRange(2, 2)
      composer.dispatchEvent(new Event("input", { bubbles: true }))
      composer.value = "@in"
      composer.setSelectionRange(3, 3)
      composer.dispatchEvent(new Event("input", { bubbles: true }))
      release()
      await flush()
      await flush()

      expect(slow).toHaveBeenCalledTimes(1)
      expect(optionLabels(element)).toEqual(["InvoicesEntity", "Issue invoiceFlowchart"])
    })
  })

  // A proposed update is parked on the message rather than saved. There is no
  // apply endpoint: the server recognises a bare affirmative, so Apply sends
  // the confirm phrase down the ordinary message pipeline.
  describe("proposal panels", () => {
    const mountWithProposal = async (proposal = {}, overrides = {}) =>
      mountController(
        "ai-assistant",
        Controller,
        panelHtml({ threadInner: messageHtml({ proposal: proposalHtml(proposal) }), ...overrides })
      )

    it("sends the confirm phrase as an ordinary turn", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountWithProposal({}, { value: "a draft" })
      const ctrl = controllerFor(application, element, "ai-assistant")

      await click(applyIn(element))
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      const [url, options] = fetchMock.mock.calls[0]
      expect(url).toBe("/messages")
      expect(options.body).toBeInstanceOf(FormData)
      expect(options.body.get("body")).toBe(CONFIRM_PHRASE)
      expect(options.body.get("conversation_id")).toBe("conv-1")
      expect(options.body.getAll("images[]")).toEqual([])
      // The turn locks the composer and arms the watchdog exactly as a typed
      // message does.
      expect(ctrl.busy).toBe(true)
      expect(sendIn(element).classList.contains("hidden")).toBe(true)
      // A draft the admin was already writing is theirs, not the apply's.
      expect(composerIn(element).value).toBe("a draft")
    })

    it("takes both buttons down and says what it is doing", async () => {
      mockFetch(202)
      const { element } = await mountWithProposal()
      const panel = panelsIn(element)[0]

      await click(applyIn(panel))
      await flush()

      expect(applyIn(panel).disabled).toBe(true)
      expect(refineIn(panel).disabled).toBe(true)
      expect(applyLabelIn(panel).textContent).toBe(APPLYING_LABEL)
    })

    it("spends one round on a double-click", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountWithProposal()
      const apply = applyIn(element)

      await click(apply)
      await click(apply)
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
    })

    it("refuses while another turn is already running", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountWithProposal({}, { value: "hello" })

      await click(sendIn(element))
      await flush()
      await click(applyIn(element))
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      expect(fetchMock.mock.calls[0][1].body.get("body")).toBe("hello")
    })

    it("does nothing when the button carries no phrase", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountWithProposal({ reply: "" })

      await click(applyIn(element))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("applyProposal() without an event has nothing to confirm", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountWithProposal()
      const ctrl = controllerFor(application, element, "ai-assistant")

      expect(() => ctrl.applyProposal()).not.toThrow()
      await flush()
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("sends from a button that is not inside a panel", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountWithProposal()
      const ctrl = controllerFor(application, element, "ai-assistant")
      element.insertAdjacentHTML(
        "beforeend",
        `<button type="button" id="loose-apply" data-action="click->ai-assistant#applyProposal" data-ai-assistant-reply-param="${CONFIRM_PHRASE}">Apply</button>`
      )
      await tick()

      await click(element.querySelector("#loose-apply"))
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      expect(ctrl.applyingPanel).toBeNull()
    })

    it("sends from a call that carries no button at all", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountWithProposal()
      const ctrl = controllerFor(application, element, "ai-assistant")

      ctrl.applyProposal({ preventDefault: () => {}, params: { reply: CONFIRM_PHRASE } })
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      expect(ctrl.applyingPanel).toBeNull()
    })

    // A refused apply must leave the draft alone and hand the panel back, or
    // the only way to retry is a reload.
    it("hands the panel back when the server refuses the turn", async () => {
      mockFetch(422, { json: { errors: ["No."] } })
      const { application, element } = await mountWithProposal({}, { value: "a draft" })
      const ctrl = controllerFor(application, element, "ai-assistant")
      const panel = panelsIn(element)[0]

      await click(applyIn(panel))
      await flush()

      expect(composerIn(element).value).toBe("a draft")
      expect(applyIn(panel).disabled).toBe(false)
      expect(refineIn(panel).disabled).toBe(false)
      expect(applyLabelIn(panel).textContent).toBe(APPLY_LABEL)
      expect(errorIn(element).textContent).toBe("No.")
      expect(ctrl.busy).toBe(false)
      expect(ctrl.applyingPanel).toBeNull()
    })

    it("hands the panel back when the apply never reaches the server", async () => {
      mockFetch(0, { reject: true })
      const { element } = await mountWithProposal()
      const panel = panelsIn(element)[0]

      await click(applyIn(panel))
      await flush()

      expect(applyIn(panel).disabled).toBe(false)
      expect(composerIn(element).value).toBe("")
    })

    it("tolerates a panel rendered without an apply label", async () => {
      mockFetch(202)
      const { element } = await mountWithProposal({ applyLabel: false })
      const panel = panelsIn(element)[0]

      await click(applyIn(panel))
      await flush()

      expect(applyIn(panel).disabled).toBe(true)
      expect(applyLabelIn(panel)).toBeNull()
    })

    it("puts the caret in the composer to refine, without a request", async () => {
      const fetchMock = mockFetch(202)
      const { element } = await mountWithProposal()

      await click(refineIn(element))

      expect(document.activeElement).toBe(composerIn(element))
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("refineProposal() has nothing to focus without a composer", async () => {
      const { application, element } = await mountWithProposal({}, { omitComposer: true })
      const ctrl = controllerFor(application, element, "ai-assistant")

      expect(() => ctrl.refineProposal()).not.toThrow()
    })

    describe("retiring a proposal a newer one has replaced", () => {
      // The server always applies the latest proposal in the thread, so an
      // older panel's Apply button would promise something it would not do.
      it("strips the older panel's actions and says why", async () => {
        const { element } = await mountWithProposal()
        const stale = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML(
          "beforeend",
          messageHtml({ body: "Newer", proposal: proposalHtml({}) })
        )
        await tick()

        expect(stale.getAttribute("data-proposal")).toBe("superseded")
        expect(applyIn(stale)).toBeNull()
        expect(refineIn(stale)).toBeNull()
        expect(noteIn(stale).textContent).toBe(SUPERSEDED_LABEL)
        expect(noteIn(stale).classList.contains("hidden")).toBe(false)

        const fresh = panelsIn(element)[1]
        expect(fresh.getAttribute("data-proposal")).toBe("pending")
        expect(applyIn(fresh)).not.toBeNull()
      })

      it("leaves an already-applied panel alone", async () => {
        const { element } = await mountWithProposal({ state: "applied", applyButton: false, refineButton: false })
        const applied = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ proposal: proposalHtml({}) }))
        await tick()

        expect(applied.getAttribute("data-proposal")).toBe("applied")
      })

      it("retires a panel appended on its own, without a bubble around it", async () => {
        const { element } = await mountWithProposal()
        const stale = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML("beforeend", proposalHtml({}))
        await tick()

        expect(stale.getAttribute("data-proposal")).toBe("superseded")
      })

      it("leaves the transcript alone when nothing that arrives is a proposal", async () => {
        const { element } = await mountWithProposal()
        const pending = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ body: "Just a reply" }))
        await tick()

        expect(pending.getAttribute("data-proposal")).toBe("pending")
        expect(applyIn(pending)).not.toBeNull()
      })

      it("disables Discard while Apply is in flight and hands it back on refusal", async () => {
        mockFetch(422, { json: { errors: [ "No." ] } })
        const { element } = await mountWithProposal({ discard: true })
        const panel = panelsIn(element)[0]

        await click(applyIn(panel))
        await flush()

        expect(discardButtonIn(panel).disabled).toBe(false)
        expect(applyIn(panel).disabled).toBe(false)
      })

      it("disables Discard the moment Apply is pressed", async () => {
        mockFetch(202)
        const { element } = await mountWithProposal({ discard: true })
        const panel = panelsIn(element)[0]

        const clickEvent = new Event("click", { bubbles: true, cancelable: true })
        applyIn(panel).dispatchEvent(clickEvent)
        expect(discardButtonIn(panel).disabled).toBe(true)
        await flush()
      })

      it("disables a Discard button that is the marked host", async () => {
        mockFetch(202)
        const { element } = await mountWithProposal({ discard: "button" })
        const panel = panelsIn(element)[0]

        const clickEvent = new Event("click", { bubbles: true, cancelable: true })
        applyIn(panel).dispatchEvent(clickEvent)
        expect(discardButtonIn(panel).disabled).toBe(true)
        await flush()
      })

      it("removes Discard when a newer proposal arrives", async () => {
        const { element } = await mountWithProposal({ discard: true })
        const stale = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML("beforeend", proposalHtml({}))
        await tick()

        expect(discardHostIn(stale)).toBeNull()
        expect(discardButtonIn(stale)).toBeNull()
      })

      it("removes a Discard button that is the marked host", async () => {
        const { element } = await mountWithProposal({ discard: "button" })
        const stale = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML("beforeend", proposalHtml({}))
        await tick()

        expect(discardHostIn(stale)).toBeNull()
      })

      it("pins the proposal message id on Apply when the button carries one", async () => {
        const fetchMock = mockFetch(202)
        const { element } = await mountWithProposal({ messageId: 88 })

        await click(applyIn(element))
        await flush()

        expect(fetchMock.mock.calls[0][1].body.get("proposal_message_id")).toBe("88")
      })

      it("omits the pin when the button carries no message id", async () => {
        const fetchMock = mockFetch(202)
        const { element } = await mountWithProposal()

        await click(applyIn(element))
        await flush()

        expect(fetchMock.mock.calls[0][1].body.get("proposal_message_id")).toBeNull()
      })

      it("omits a blank pin", async () => {
        const fetchMock = mockFetch(202)
        const { application, element } = await mountWithProposal()
        const ctrl = controllerFor(application, element, "ai-assistant")

        ctrl.applyProposal({ preventDefault: () => {}, params: { reply: CONFIRM_PHRASE, messageId: "  " } })
        await flush()

        expect(fetchMock.mock.calls[0][1].body.get("proposal_message_id")).toBeNull()
      })

      it("tolerates a stale panel with no note to write into", async () => {
        const { element } = await mountWithProposal({ note: false })
        const stale = panelsIn(element)[0]

        threadIn(element).insertAdjacentHTML("beforeend", proposalHtml({}))
        await tick()

        expect(stale.getAttribute("data-proposal")).toBe("superseded")
        expect(applyIn(stale)).toBeNull()
        expect(noteIn(stale)).toBeNull()
      })
    })

    // Applying consumes the proposal server-side, and the server re-broadcasts
    // that message so its panel re-renders as applied. That lands in the middle
    // of the turn, as an assistant bubble replacing an assistant bubble.
    describe("the server re-rendering a consumed proposal mid-turn", () => {
      // Replace a message by dom_id, the way Turbo does.
      const replaceMessage = (element, id, html) => {
        const old = element.querySelector(`#${id}`)
        const fresh = document.createElement("div")
        fresh.innerHTML = html
        fresh.firstElementChild.id = id
        old.replaceWith(fresh.firstElementChild)
      }

      const mountWithIdentifiedProposal = async (value = "") => {
        const mounted = await mountController(
          "ai-assistant",
          Controller,
          panelHtml({ threadInner: messageHtml({ proposal: proposalHtml({}) }), value })
        )
        threadIn(mounted.element).querySelector("[data-role]").id = "message_1"
        return mounted
      }

      it("does not end the turn when a bubble is re-rendered where it already was", async () => {
        mockFetch(202)
        const { application, element } = await mountWithIdentifiedProposal()
        const ctrl = controllerFor(application, element, "ai-assistant")

        await click(applyIn(element))
        await flush()
        expect(ctrl.busy).toBe(true)

        replaceMessage(
          element,
          "message_1",
          messageHtml({ proposal: proposalHtml({ state: "applied", applyButton: false, refineButton: false }) })
        )
        await tick()

        // The reply is still being written: the composer stays locked and Stop
        // stays up until it actually arrives.
        expect(ctrl.busy).toBe(true)
        expect(element.querySelector("[data-ai-assistant-target='stopButton']").classList.contains("hidden")).toBe(false)

        threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ body: "Done" }))
        await tick()
        expect(ctrl.busy).toBe(false)
      })

      it("does not read the replaced applied panel as a new proposal", async () => {
        mockFetch(202)
        const { element } = await mountWithIdentifiedProposal()
        threadIn(element).insertAdjacentHTML(
          "beforeend",
          messageHtml({ body: "Older", proposal: proposalHtml({}) })
        )
        await tick()
        const other = panelsIn(element)[1]
        expect(other.getAttribute("data-proposal")).toBe("pending")

        replaceMessage(
          element,
          "message_1",
          messageHtml({ proposal: proposalHtml({ state: "applied", applyButton: false, refineButton: false }) })
        )
        await tick()

        expect(other.getAttribute("data-proposal")).toBe("pending")
        expect(applyIn(other)).not.toBeNull()
      })

      // The panel whose Apply started the turn is the one the server replaces,
      // so the held reference outlives its node.
      it("survives the panel it is holding being detached", async () => {
        mockFetch(202)
        const { application, element } = await mountWithIdentifiedProposal()
        const ctrl = controllerFor(application, element, "ai-assistant")
        const held = panelsIn(element)[0]

        await click(applyIn(held))
        await flush()
        // A committed turn belongs to the server; the panel is let go of, which
        // is what keeps a detached node out of the refusal path.
        expect(ctrl.applyingPanel).toBeNull()

        replaceMessage(
          element,
          "message_1",
          messageHtml({ proposal: proposalHtml({ state: "applied", applyButton: false, refineButton: false }) })
        )
        await tick()

        expect(held.isConnected).toBe(false)
        expect(panelsIn(element)[0].getAttribute("data-proposal")).toBe("applied")
      })

      // A refused apply never reaches the server, so no re-render can race it —
      // but holding a node that is no longer in the document must not throw.
      it("releases a detached panel without throwing", async () => {
        mockFetch(500, { json: { errors: [ "nope" ] } })
        const { application, element } = await mountWithIdentifiedProposal()
        const ctrl = controllerFor(application, element, "ai-assistant")
        const held = panelsIn(element)[0]

        await click(applyIn(held))
        held.remove()
        await flush()

        expect(ctrl.applyingPanel).toBeNull()
        expect(applyLabelIn(held).textContent).toBe(APPLY_LABEL)
        expect(errorIn(element).textContent).toBe("nope")
      })

      // The running flag is delivered as a replacement of itself, so the
      // in-place check must not swallow it.
      it("still ends the turn on a stopped flag replaced in place", async () => {
        mockFetch(202)
        const { application, element } = await mountWithIdentifiedProposal("hello")
        const ctrl = controllerFor(application, element, "ai-assistant")

        await click(sendIn(element))
        await flush()
        expect(ctrl.busy).toBe(true)

        threadIn(element).insertAdjacentHTML(
          "beforeend",
          `<div id="ai_assistant_running" data-running="true"></div>`
        )
        await tick()
        expect(ctrl.busy).toBe(true)

        replaceMessage(element, "ai_assistant_running", `<div data-running="false"></div>`)
        await tick()

        expect(ctrl.busy).toBe(false)
      })

      // The in-place check keys on the dom_id: an assistant bubble arriving
      // beside unrelated removals is a real reply, not a re-render.
      it("ends the turn on a bubble that arrives beside unrelated removals", async () => {
        mockFetch(202)
        const { application, element } = await mountWithIdentifiedProposal("hello")
        const ctrl = controllerFor(application, element, "ai-assistant")
        const thread = threadIn(element)
        thread.insertAdjacentHTML("beforeend", `<span id="something_else"></span>`)
        thread.appendChild(document.createTextNode("stray"))

        await click(sendIn(element))
        await flush()
        expect(ctrl.busy).toBe(true)

        const reply = document.createElement("div")
        reply.id = "message_2"
        reply.setAttribute("data-role", "assistant")
        thread.replaceChildren(reply)
        await tick()

        expect(ctrl.busy).toBe(false)
      })
    })
  })

  describe("question cards", () => {
    const mountWithQuestions = async (card = {}, overrides = {}, extraThread = "") =>
      mountController(
        "ai-assistant",
        Controller,
        panelHtml({
          threadInner: messageHtml({ proposal: questionsHtml(card) }) + extraThread,
          ...overrides
        })
      )

    const answerEvent = (card, body) => ({
      preventDefault: () => {},
      currentTarget: card,
      detail: { body }
    })

    it("holds the card, swaps the Send label, and posts the composed body", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountWithQuestions()
      const ctrl = controllerFor(application, element, "ai-assistant")
      const card = cardsIn(element)[0]

      ctrl.answerQuestions(answerEvent(card, "Hours\nMon"))
      expect(card.getAttribute("data-questions")).toBe("held")
      expect(card.querySelector("[data-questions-send-label]").textContent).toBe("Sending…")
      expect(card.querySelector("input").disabled).toBe(true)
      expect(card.querySelector("[data-questions-fieldset]").classList.contains("opacity-60")).toBe(true)
      await flush()

      expect(fetchMock.mock.calls[0][1].body.get("body")).toBe("Hours\nMon")
      expect(card.getAttribute("data-questions")).toBe("closed")
      expect(card.querySelector("[data-questions-answered]").classList.contains("hidden")).toBe(false)
      expect(card.querySelector("[data-questions-subtitle]").classList.contains("hidden")).toBe(true)
      expect(card.querySelector("[data-questions-footer]").classList.contains("hidden")).toBe(true)
      expect(card.querySelector("[data-questions-input]").classList.contains("hidden")).toBe(true)
      expect(card.querySelector("input[type='radio']").checked).toBe(false)
      expect(card.querySelector("input[type='checkbox']").checked).toBe(false)
    })

    it("releases the hold when the send is refused", async () => {
      mockFetch(422, { json: { errors: [ "No." ] } })
      const { application, element } = await mountWithQuestions()
      const ctrl = controllerFor(application, element, "ai-assistant")
      const card = cardsIn(element)[0]

      ctrl.answerQuestions(answerEvent(card, "Hours\nMon"))
      await flush()

      expect(card.getAttribute("data-questions")).toBe("open")
      expect(card.querySelector("[data-questions-send-label]").textContent).toBe("Send answers")
      expect(card.querySelector("input").disabled).toBe(false)
      expect(card.querySelector("[data-questions-fieldset]").classList.contains("opacity-60")).toBe(false)
      expect(errorIn(element).textContent).toBe("No.")
      expect(ctrl.answeringCard).toBeNull()
    })

    it("does nothing when the thread cannot spend a turn or the body is blank", async () => {
      const fetchMock = mockFetch(202)
      const { application, element } = await mountWithQuestions({}, { value: "hello" })
      const ctrl = controllerFor(application, element, "ai-assistant")
      const card = cardsIn(element)[0]

      await click(sendIn(element))
      await flush()
      ctrl.answerQuestions(answerEvent(card, "Hours\nMon"))
      await flush()
      expect(fetchMock).toHaveBeenCalledOnce()

      ctrl.busy = false
      expect(() => ctrl.answerQuestions()).not.toThrow()
      ctrl.answerQuestions({ preventDefault: () => {}, currentTarget: card, detail: { body: "  " } })
      await flush()
      expect(fetchMock).toHaveBeenCalledOnce()
    })

    it("closes every open card after a typed send", async () => {
      mockFetch(202)
      const { element } = await mountWithQuestions({}, { value: "typed yes" })
      const card = cardsIn(element)[0]

      await click(sendIn(element))
      await flush()

      expect(card.getAttribute("data-questions")).toBe("closed")
    })

    it("closes every open card after Apply", async () => {
      mockFetch(202)
      const { element } = await mountController(
        "ai-assistant",
        Controller,
        panelHtml({
          threadInner: messageHtml({
            proposal: `${proposalHtml({})}${questionsHtml({})}`
          })
        })
      )
      const card = cardsIn(element)[0]

      await click(applyIn(element))
      await flush()

      expect(card.getAttribute("data-questions")).toBe("closed")
    })

    it("closes older open cards when a new open card arrives", async () => {
      const { element } = await mountWithQuestions()
      const older = cardsIn(element)[0]

      threadIn(element).insertAdjacentHTML(
        "beforeend",
        messageHtml({ body: "Newer", proposal: questionsHtml({}) })
      )
      await tick()

      expect(older.getAttribute("data-questions")).toBe("closed")
      expect(cardsIn(element)[1].getAttribute("data-questions")).toBe("open")
    })

    it("retires a card that arrives as the open node itself", async () => {
      const { element } = await mountWithQuestions()
      const older = cardsIn(element)[0]

      threadIn(element).insertAdjacentHTML("beforeend", questionsHtml({}))
      await tick()

      expect(older.getAttribute("data-questions")).toBe("closed")
    })

    it("leaves open cards alone when the arrival is not an open card", async () => {
      const { element } = await mountWithQuestions()
      const open = cardsIn(element)[0]

      threadIn(element).insertAdjacentHTML("beforeend", messageHtml({ body: "Just a reply" }))
      threadIn(element).appendChild(document.createTextNode("stray"))
      await tick()

      expect(open.getAttribute("data-questions")).toBe("open")
    })

    it("tolerates a card missing the slots a close would write into", async () => {
      mockFetch(202)
      const { application, element } = await mountWithQuestions({
        sendLabel: false,
        answered: false,
        subtitle: false,
        footer: false,
        inputs: false,
        fieldset: false
      })
      const ctrl = controllerFor(application, element, "ai-assistant")
      const card = cardsIn(element)[0]

      expect(() => ctrl.answerQuestions(answerEvent(card, "Hours\nMon"))).not.toThrow()
      await flush()
      expect(card.getAttribute("data-questions")).toBe("closed")
    })

    it("hold and close without a card are no-ops", async () => {
      const { application, element } = await mountWithQuestions()
      const ctrl = controllerFor(application, element, "ai-assistant")

      expect(() => ctrl.answerQuestions({ preventDefault: () => {}, detail: { body: "Hours\nMon" } })).not.toThrow()
      await flush()
      expect(ctrl.answeringCard).toBeNull()
    })
  })

  it("disconnects the mutation observer", async () => {
    const { application, element } = await mountController("ai-assistant", Controller, panelHtml())
    const ctrl = controllerFor(application, element, "ai-assistant")
    expect(ctrl.observer).toBeTruthy()
    element.remove()
    await tick()
    expect(ctrl.observer).toBeNull()
    application.stop()
  })
})
