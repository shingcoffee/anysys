import { Controller } from "@hotwired/stimulus"

// `@` menu behaviour. Artifact names contain spaces ("Purchase Order"), so the
// query is allowed a few words before the text is treated as ordinary prose
// again and the menu gets out of the way.
const MENTION = { maxQueryLength: 40, maxQueryWords: 3, maxRows: 8, ttlMs: 15_000, blurMs: 180 }
const MENTION_OPTION_ID = "ai-assistant-mention"
// The "no match" row is an option too, so `aria-activedescendant` has somewhere
// to point when the query matches nothing.
const MENTION_EMPTY_ID = "ai-assistant-mention-empty"
// AiAssistant::Stream::RUNNING_ID. The flag arrives as a replacement for this
// id, so it is matched by id rather than by Stimulus target on the way in.
const RUNNING_FLAG_ID = "ai_assistant_running"
// Stands in for "the menu belongs to no mention". A real one always sits at a
// non-negative offset, so this can never be mistaken for live.
const NO_MENTION = { at: -1, query: "" }
// How far from the foot of the transcript still counts as "reading the latest".
// A reply that lands while the admin is this close gets scrolled into view; any
// further up and the viewport is left where it was put.
const PINNED_SLACK_PX = 80

export default class extends Controller {
  static targets = [
    "thread",
    "composer",
    "sendButton",
    "stopButton",
    "regenerateButton",
    "jumpButton",
    "images",
    "previews",
    "error",
    "turnsHint",
    "mentionMenu",
    "mentionList",
    "runningFlag",
    "newChatButton"
  ]

  static values = {
    url: String,
    stopUrl: { type: String, default: "" },
    regenerateUrl: { type: String, default: "" },
    mentionsUrl: { type: String, default: "" },
    conversationId: { type: String, default: "" },
    mentionKinds: { type: Object, default: {} },
    cooldownMs: { type: Number, default: 1200 },
    // How long a turn may go without any stream traffic before the panel
    // decides the connection, not the model, is the problem.
    watchdogMs: { type: Number, default: 180_000 },
    // Fail open: the round cap lives on the server, so an absent budget must
    // never be read as "spent" and lock the composer.
    turnsRemaining: { type: Number, default: Number.POSITIVE_INFINITY },
    turnsWarningAt: { type: Number, default: 5 },
    maxFiles: { type: Number, default: 8 },
    maxBytes: { type: Number, default: 5 * 1024 * 1024 },
    accept: { type: String, default: "image/jpeg,image/png,image/gif,image/webp" },
    tooManyTemplate: { type: String, default: "You can attach at most {count} files." },
    typeLabel: { type: String, default: "That image type is not allowed." },
    sizeTemplate: { type: String, default: "Each image must be {size} or smaller." },
    sizeLabel: { type: String, default: "5MB" },
    maxTotalBytes: { type: Number, default: 20 * 1024 * 1024 },
    totalSizeLabel: { type: String, default: "Attached images must total 20MB or less." },
    copyLabel: { type: String, default: "Copy" },
    copiedLabel: { type: String, default: "Copied" },
    copyFailedLabel: { type: String, default: "Could not copy" },
    removeImageLabel: { type: String, default: "Remove image" },
    removeMark: { type: String, default: "×" },
    stopLabel: { type: String, default: "Stop" },
    stoppingLabel: { type: String, default: "Stopping…" },
    sendFailedLabel: { type: String, default: "Could not send the message." },
    regenerateFailedLabel: { type: String, default: "Could not regenerate the reply." },
    stopFailedLabel: { type: String, default: "Could not stop the reply." },
    connectionLostLabel: {
      type: String,
      default: "Lost contact with the server. Reload the page to see the reply."
    },
    mentionEmptyLabel: { type: String, default: "No match" },
    proposalApplyLabel: { type: String, default: "Apply changes" },
    proposalApplyingLabel: { type: String, default: "Applying…" },
    proposalSupersededLabel: { type: String, default: "Replaced by a newer proposal." },
    questionsSendLabel: { type: String, default: "Send answers" },
    questionsSendingLabel: { type: String, default: "Sending…" },
    turnsRemainingTemplate: { type: String, default: "{count} messages left in this chat." },
    turnsExhaustedLabel: {
      type: String,
      default: "This chat has reached its limit. Start a new chat to continue."
    }
  }

  conversationIdValueChanged(conversationId) {
    this.dispatch("conversationChanged", { detail: { conversationId } })
  }

  connect() {
    this.busy = false
    this.stopping = false
    this.lastSentAt = 0
    this.files = []
    this.previewUrls = []
    this.mentions = []
    this.mentionsLoadedAt = 0
    this.mentionsRequest = null
    this.mentionMatches = []
    this.mentionIndex = 0
    this.mentionAnchor = NO_MENTION
    this.mentionOpen = false
    this.mentionBlurTimer = null
    this.watchdogTimer = null
    // The proposal panel whose Apply button started the turn in flight, so a
    // refused send can hand it back instead of leaving a dead button.
    this.applyingPanel = null
    // The question card whose Send/Skip started the turn, released on refusal.
    this.answeringCard = null
    // A freshly rendered thread opens at its foot, so the reader starts pinned.
    this.pinned = true
    this.lastTouchY = null
    this.idlePlaceholder = this.hasComposerTarget ? this.composerTarget.placeholder : ""
    this.observer = new MutationObserver((mutations) => this.#onMutations(mutations))
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.#scrollToBottom()
    // Seeded from the server's flag rather than assumed idle: a reload in the
    // middle of a turn would otherwise show Send, with no way to cancel and
    // Enter free to start a second concurrent turn.
    this.#setRunning(this.#flagSaysRunning())
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
    if (this.copyTimer) {
      clearTimeout(this.copyTimer)
      this.copyTimer = null
    }
    this.#clearWatchdog()
    this.#cancelDeferredClose()
    this.#revokePreviews()
  }

  // Guards against a reply already in flight, a held Enter key, and a thread
  // that has spent its rounds. The server enforces all three independently.
  send(event) {
    if (event) event.preventDefault()
    if (!this.#canSpendTurn()) return

    const body = this.#composerValue()
    const files = this.#fileList()
    if (!body && files.length === 0) return
    const error = this.#validateFiles(files)
    if (error) {
      this.#setError(error)
      return
    }

    this.#setComposer("")
    this.#submit(body, files, true)
  }

  // Replays the last user turn. Shares `send`'s guards because it spends the
  // same round budget and runs through the same reply job.
  regenerate(event) {
    if (event) event.preventDefault()
    if (!this.regenerateUrlValue) return
    if (!this.#canSpendTurn()) return

    this.lastSentAt = Date.now()
    this.#setRunning(true)
    this.#closeMentions()
    void this.#regenerate()
  }

  // Confirms this panel's proposal: posts the confirm phrase through the
  // ordinary message pipeline, pinned to this message when the button
  // carries a message id.
  applyProposal(event) {
    if (event) event.preventDefault()
    if (!this.#canSpendTurn()) return

    const params = (event && event.params) || {}
    const reply = String(params.reply || "").trim()
    if (!reply) return

    const extra = {
      proposal_message_id: params.messageId != null ? String(params.messageId).trim() : null
    }

    // Both buttons go down together: a second click would spend a second round
    // on a proposal the first one has already confirmed.
    this.#holdProposal(this.#proposalPanel(event), true)
    this.#submit(reply, [], false, extra)
  }

  // Posts the composed answers (or the skip phrase) as an ordinary turn.
  // The card is held while the request is in flight and closed on success.
  answerQuestions(event) {
    if (event) event.preventDefault()
    if (!this.#canSpendTurn()) return

    const body = String((event && event.detail && event.detail.body) || "").trim()
    if (!body) return

    this.#holdQuestions((event && event.currentTarget) || null, true)
    this.#submit(body, [], false)
  }

  // Refining is a conversation, not a request: the composer is where the
  // adjustment gets written, so this only puts the caret there.
  refineProposal(event) {
    if (event) event.preventDefault()
    if (!this.hasComposerTarget) return

    this.#focusComposer()
    this.composerTarget.scrollIntoView({ block: "nearest" })
  }

  // Acknowledged locally before the request leaves: a Stop that changes nothing
  // on screen reads as a dead button and gets pressed again.
  stop(event) {
    if (event) event.preventDefault()
    if (!this.stopUrlValue || this.stopping) return

    this.#setStopping(true)
    void this.#stop()
  }

  // Copies the reply the button belongs to, falling back to the latest turn.
  copy(event) {
    if (event) event.preventDefault()

    const button = (event && event.currentTarget) || null
    const message = (button && button.closest("[data-role]")) || this.#lastMessage()
    if (!message) return

    const text = message.getAttribute("data-body") || message.textContent || ""
    void this.#copyText(text, button)
  }

  attach(event) {
    if (event) event.preventDefault()
    if (!this.hasImagesTarget) return

    this.imagesTarget.click()
  }

  // `this.files` is the only record of what will be sent, so a new selection is
  // added to it rather than replacing it. Emptying the control afterwards is
  // what makes re-picking a removed filename fire `change` at all.
  pickImages() {
    if (!this.hasImagesTarget) return

    const picked = Array.from(this.imagesTarget.files || [])
    this.imagesTarget.value = ""
    this.#commitFiles([ ...this.#fileList(), ...picked ])
  }

  removeImage(event) {
    if (event) event.preventDefault()
    const button = event && event.currentTarget
    // Not `Number.isNaN`: `Number(undefined)` is NaN but `Number(null)` is 0,
    // which would pass the guard and drop the first attachment instead.
    const index = Number(button?.dataset?.index)
    if (!Number.isInteger(index) || index < 0) return

    this.#commitFiles(this.#fileList().filter((_file, i) => i !== index))
  }

  keydown(event) {
    // A key pressed at an IME candidate list belongs to the IME, not to the
    // composer: Enter there commits the candidate, and acting on it would
    // complete a mention or post half-typed pinyin as the message.
    if (event.isComposing) return
    if (this.#mentionKeydown(event)) return
    if (event.key !== "Enter" || event.shiftKey) return
    event.preventDefault()
    this.send()
  }

  // The composer's own input handler: grow the box, then keep the `@` menu in
  // step with where the caret now sits. Also bound to `compositionend`, which
  // is where the menu catches up with what the IME finally committed.
  compose(event) {
    this.resize()
    // Pinyin on its way to becoming Chinese is not a name to match against.
    if (event && event.isComposing) return

    void this.#syncMentions()
  }

  // Blur is deferred: a tap on a row blurs the composer first, and closing
  // synchronously would unmount the option before its click landed.
  closeMentions() {
    this.#deferCloseMentions()
  }

  // Bound on the menu itself so its padding and scrollbar count as part of it:
  // keeping focus (and the caret) in the composer is what stops `blur` closing
  // the menu out from under a click or a scrollbar drag.
  preventBlur(event) {
    this.#cancelDeferredClose()
    // pointerdown is left alone so a tap-drag can still scroll the list;
    // mousedown is what stops the desktop caret from leaving the composer.
    if (event.type === "mousedown") event.preventDefault()
  }

  // Whether the reader is still at the foot of the transcript decides what an
  // arriving reply is allowed to do to the viewport.
  threadScrolled() {
    this.pinned = this.#atBottom()
    this.#setJumpVisible(!this.pinned)
  }

  // Unpinning happens here rather than in `threadScrolled` because `scroll` is
  // coalesced to roughly one event a frame: a fast stream mutates the thread
  // several times inside that window, and every one of those mutations would
  // still read `pinned` as true and snap the viewport back down.
  userScrolled(event) {
    if (!this.#readingBack(event)) return

    this.pinned = false
    this.#setJumpVisible(true)
  }

  jumpToLatest(event) {
    if (event) event.preventDefault()

    this.pinned = true
    this.#scrollToBottom()
    this.#setJumpVisible(false)
  }

  // Completes the mention the admin clicked. Bound in JS rather than the
  // template because the rows are built from the endpoint's response.
  pickMention(event) {
    if (event) event.preventDefault()
    this.#cancelDeferredClose()

    const row = event && event.currentTarget
    this.#insertMention(row ? Number(row.dataset.index) : this.mentionIndex)
  }

  // Grow the composer with its content (capped by max-h in the template) so a
  // multi-line prompt stays readable while it is being written.
  resize() {
    if (!this.hasComposerTarget) return

    this.composerTarget.style.height = "auto"
    this.composerTarget.style.height = `${this.composerTarget.scrollHeight}px`
  }

  usePrompt(event) {
    if (event) event.preventDefault()
    if (!this.hasComposerTarget) return

    const source = event && event.currentTarget
    const fromData = source && source.getAttribute ? source.getAttribute("data-prompt") : ""
    const prompt = (fromData && fromData.trim()) || (source && source.textContent ? source.textContent.trim() : "")
    if (!prompt) return

    this.#setComposer(prompt)
    this.composerTarget.focus()
  }

  // Starting a chat belongs to the chat list, which is not an ancestor of the
  // composer, so the request travels as an event the list binds to on window.
  newChat(event) {
    if (event) event.preventDefault()

    this.dispatch("newChat")
  }

  // Every path that spends a round: a turn already running, a held key inside
  // the cooldown, and a thread with no budget left. The server enforces all
  // three independently.
  #canSpendTurn() {
    return !this.busy && !this.#cooling() && !this.#turnsExhausted()
  }

  // The one submit pipeline. `restore` says whether a refused send belongs back
  // in the composer — it does for a typed message, and it must not for an
  // applied proposal, whose phrase would otherwise clobber a waiting draft.
  #submit(body, files, restore, extra = {}) {
    this.lastSentAt = Date.now()
    this.#setRunning(true)
    this.#closeMentions()
    void this.#post(body, files, restore, extra)
  }

  async #post(body, files, restore, extra = {}) {
    const form = new FormData()
    form.append("body", body)
    form.append("conversation_id", this.conversationIdValue)
    files.forEach((file) => form.append("images[]", file))
    Object.keys(extra).forEach((key) => {
      const value = extra[key]
      if (value == null || value === "") return

      form.append(key, String(value))
    })

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.#csrfToken(),
          Accept: "application/json"
        },
        body: form
      })
      if (!response.ok) {
        this.#sendRefused(body, restore)
        this.#setError(await this.#sendErrorMessage(response))
      } else {
        this.#commitFiles([])
        this.#setError("")
        this.#spendTurn()
        this.#focusComposer()
        // The turn is the server's now; the panel that started it keeps its
        // buttons down for good. Every open question card closes in place.
        this.applyingPanel = null
        this.#closeOpenQuestions()
      }
    } catch {
      this.#sendRefused(body, restore)
      this.#setError(this.sendFailedLabelValue)
    }
  }

  // A turn that never started gives everything back: the composer gets its text
  // and the proposal panel gets its buttons, so either can be tried again.
  #sendRefused(body, restore) {
    if (restore) this.#setComposer(body)
    this.#setRunning(false)
    this.#holdProposal(this.applyingPanel, false)
    this.#holdQuestions(this.answeringCard, false)
  }

  async #regenerate() {
    try {
      const response = await fetch(this.regenerateUrlValue, {
        method: "POST",
        headers: this.#jsonHeaders(),
        body: this.#conversationBody()
      })
      if (!response.ok) {
        this.#setRunning(false)
        this.#setError(this.regenerateFailedLabelValue)
      } else {
        this.#setError("")
        this.#focusComposer()
      }
    } catch {
      this.#setRunning(false)
      this.#setError(this.regenerateFailedLabelValue)
    }
  }

  async #stop() {
    try {
      const response = await fetch(this.stopUrlValue, {
        method: "POST",
        headers: this.#jsonHeaders(),
        body: this.#conversationBody()
      })
      // A refused stop leaves the turn running, so saying nothing would read as
      // "stopped" while the reply keeps arriving. The button goes back to Stop
      // because pressing it again is the only thing left to try.
      if (!response.ok) {
        this.#setStopping(false)
        this.#setError(this.stopFailedLabelValue)
      }
    } catch {
      this.#setStopping(false)
      this.#setError(this.stopFailedLabelValue)
    }
  }

  #jsonHeaders() {
    return {
      "X-CSRF-Token": this.#csrfToken(),
      Accept: "application/json",
      "Content-Type": "application/json"
    }
  }

  #conversationBody() {
    return JSON.stringify({ conversation_id: this.conversationIdValue })
  }

  async #copyText(text, button) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text)
        this.#flashCopy(button, true)
        return
      }
    } catch {
      // Fall through to the failed label.
    }
    this.#flashCopy(button, false)
  }

  // --- proposal panels ----------------------------------------------------
  //
  // A proposed update is parked on the assistant message. Apply posts the
  // confirm phrase through the ordinary pipeline; Discard is a server form.
  // This code only holds a panel in flight and retires older ones.

  #proposalPanel(event) {
    const button = event.currentTarget
    return button ? button.closest("[data-proposal]") : null
  }

  // Down while the turn it started is in flight, back up if that turn was
  // refused. Defensive about its own markup: a panel superseded in the meantime
  // has had its buttons taken away.
  #holdProposal(panel, held) {
    this.applyingPanel = held ? panel : null
    if (!panel) return

    panel.querySelectorAll("[data-proposal-apply], [data-proposal-refine], [data-proposal-discard]").forEach((el) => {
      if (el.tagName === "BUTTON") {
        el.disabled = held
        return
      }
      el.querySelectorAll("button").forEach((button) => {
        button.disabled = held
      })
    })
    const label = panel.querySelector("[data-proposal-apply-label]")
    if (!label) return

    label.textContent = held ? this.proposalApplyingLabelValue : this.proposalApplyLabelValue
  }

  // A newly parked pending proposal retires older pending panels so only
  // the newest one stays actionable. Driven by arrivals of a *pending*
  // panel, so a consumed proposal re-rendered as applied does not retire
  // everything else.
  #retireStaleProposals(mutations) {
    const arrived = this.#arrivedProposals(mutations)
    if (!arrived.length) return

    this.element.querySelectorAll("[data-proposal='pending']").forEach((panel) => {
      if (arrived.includes(panel)) return

      this.#retireProposal(panel)
    })
  }

  // A bubble arrives as one appended node, so the panel is looked for inside it
  // as well as being it.
  #arrivedProposals(mutations) {
    const found = []
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType !== 1) continue
        if (node.matches("[data-proposal='pending']")) found.push(node)
        found.push(...node.querySelectorAll("[data-proposal='pending']"))
      }
    }
    return found
  }

  #retireProposal(panel) {
    panel.setAttribute("data-proposal", "superseded")
    panel.querySelectorAll("[data-proposal-apply], [data-proposal-refine], [data-proposal-discard]").forEach((el) => el.remove())

    const note = panel.querySelector("[data-proposal-note]")
    if (!note) return

    note.textContent = this.proposalSupersededLabelValue
    note.classList.remove("hidden")
  }

  // --- question cards -----------------------------------------------------
  //
  // An open card is held while its answers are posted, released if that send
  // is refused, and closed in place on any successful turn. A newly arrived
  // open card closes older open ones, mirroring #retireStaleProposals.

  #holdQuestions(card, held) {
    this.answeringCard = held ? card : null
    if (!card) return

    card.setAttribute("data-questions", held ? "held" : "open")
    card.querySelectorAll("input, button, textarea").forEach((el) => {
      el.disabled = held
    })
    card.querySelectorAll("[data-questions-fieldset]").forEach((fieldset) => {
      fieldset.classList.toggle("opacity-60", held)
    })
    const label = card.querySelector("[data-questions-send-label]")
    if (!label) return

    label.textContent = held ? this.questionsSendingLabelValue : this.questionsSendLabelValue
  }

  #closeOpenQuestions() {
    this.element.querySelectorAll("[data-questions='open'], [data-questions='held']").forEach((card) => {
      this.#closeQuestions(card)
    })
    this.answeringCard = null
  }

  #closeStaleQuestions(mutations) {
    const arrived = this.#arrivedQuestions(mutations)
    if (!arrived.length) return

    this.element.querySelectorAll("[data-questions='open']").forEach((card) => {
      if (arrived.includes(card)) return

      this.#closeQuestions(card)
    })
  }

  #arrivedQuestions(mutations) {
    const found = []
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType !== 1) continue
        if (node.matches("[data-questions='open']")) found.push(node)
        found.push(...node.querySelectorAll("[data-questions='open']"))
      }
    }
    return found
  }

  #closeQuestions(card) {
    card.setAttribute("data-questions", "closed")
    const answered = card.querySelector("[data-questions-answered]")
    if (answered) answered.classList.remove("hidden")
    const subtitle = card.querySelector("[data-questions-subtitle]")
    if (subtitle) subtitle.classList.add("hidden")
    const footer = card.querySelector("[data-questions-footer]")
    if (footer) footer.classList.add("hidden")
    card.querySelectorAll("[data-questions-input]").forEach((el) => {
      el.classList.add("hidden")
      if (typeof el.disabled === "boolean") el.disabled = true
      el.querySelectorAll("input, textarea").forEach((input) => {
        input.disabled = true
      })
    })
    card.querySelectorAll("input[type='radio'], input[type='checkbox']").forEach((input) => {
      input.checked = false
      input.disabled = true
    })
    card.querySelectorAll("[data-questions-fieldset]").forEach((fieldset) => {
      fieldset.classList.remove("opacity-60")
    })
  }

  #onMutations(mutations) {
    // Any traffic at all means the stream is alive, so the turn gets its full
    // patience back rather than counting down from the send.
    if (this.busy) this.#armWatchdog()

    if (this.#threadTouched(mutations)) {
      if (this.pinned) this.#scrollToBottom()
      else this.#setJumpVisible(true)
    }

    // Ahead of the busy check: the node that carries a new proposal is usually
    // the same one that ends the turn. A newly arrived open question card
    // closes older open cards the same way.
    this.#retireStaleProposals(mutations)
    this.#closeStaleQuestions(mutations)

    if (!this.busy) return

    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        // Read before the in-place check below: the running flag is always
        // delivered as a replacement of itself.
        if (this.#isStoppedFlag(node)) {
          this.#setRunning(false)
          return
        }
        if (this.#isAssistantNode(node) && !this.#replacedInPlace(mutations, node)) {
          this.#setRunning(false)
          return
        }
      }
    }
  }

  // A bubble re-rendered where it already was is not the reply this turn is
  // waiting for. The server replaces a consumed proposal's message mid-turn so
  // its panel re-renders as applied, and that arrives as an assistant node
  // while the actual reply is still being written — ending the turn on it would
  // unlock the composer and drop the Stop button early.
  //
  // A replace takes the old node out and puts the new one in under the same
  // dom_id; an appended reply removes nothing. Both halves are queued in the
  // same microtask, so the whole batch is searched rather than the one record —
  // whether the removal and the insertion share a record is up to the DOM
  // implementation, and two elements cannot share an id in any of them.
  #replacedInPlace(mutations, node) {
    if (!node.id) return false

    return mutations.some((mutation) =>
      Array.from(mutation.removedNodes).some((gone) => gone.nodeType === 1 && gone.id === node.id)
    )
  }

  // Mention rows and attachment previews are rebuilt inside this element too,
  // and neither is a reason to move the transcript.
  #threadTouched(mutations) {
    if (!this.hasThreadTarget) return false

    return mutations.some((mutation) => this.threadTarget.contains(mutation.target))
  }

  #isAssistantNode(node) {
    if (!node || node.nodeType !== 1) return false
    if (node.getAttribute && node.getAttribute("data-role") === "assistant") return true
    return Boolean(node.querySelector && node.querySelector("[data-role='assistant']"))
  }

  #isStoppedFlag(node) {
    if (!node || node.nodeType !== 1) return false
    if (this.#flagStopped(node)) return true
    const nested = node.querySelector && node.querySelector("#ai_assistant_running")
    return this.#flagStopped(nested)
  }

  #flagStopped(node) {
    if (!node || node.id !== "ai_assistant_running") return false
    return String(node.getAttribute("data-running")) === "false"
  }

  // A dropped socket or a dead reply job would otherwise leave the composer
  // showing Stop for ever, with no way back short of a reload.
  #armWatchdog() {
    this.#clearWatchdog()
    if (this.watchdogMsValue <= 0) return

    this.watchdogTimer = setTimeout(() => this.#watchdogExpired(), this.watchdogMsValue)
  }

  #clearWatchdog() {
    if (!this.watchdogTimer) return

    clearTimeout(this.watchdogTimer)
    this.watchdogTimer = null
  }

  #watchdogExpired() {
    this.watchdogTimer = null
    if (!this.busy) return

    this.#setRunning(false)
    this.#setError(this.connectionLostLabelValue, true)
  }

  #cooling() {
    return Date.now() - this.lastSentAt < this.cooldownMsValue
  }

  #turnsExhausted() {
    return this.turnsRemainingValue <= 0
  }

  #spendTurn() {
    this.turnsRemainingValue = Math.max(this.turnsRemainingValue - 1, 0)
    this.#renderTurnsHint()
    this.#syncButtons()
  }

  // Only shown once the thread is close to its cap; a running counter on every
  // conversation would be noise.
  #renderTurnsHint() {
    if (!this.hasTurnsHintTarget) return

    const remaining = this.turnsRemainingValue
    const text = remaining <= 0
      ? this.turnsExhaustedLabelValue
      : remaining <= this.turnsWarningAtValue
        ? this.turnsRemainingTemplateValue.replace("{count}", String(remaining))
        : ""

    this.turnsHintTarget.textContent = text
    this.turnsHintTarget.classList.toggle("hidden", !text)
  }

  // The server's flag, not an assumption. Absent means idle: the round cap and
  // the turn state both live server-side, so a missing flag must never be read
  // as "running" and lock the composer behind a Stop that cannot resolve.
  #flagSaysRunning() {
    const flag = this.hasRunningFlagTarget
      ? this.runningFlagTarget
      : this.element.querySelector(`#${RUNNING_FLAG_ID}`)

    return Boolean(flag) && String(flag.getAttribute("data-running")) === "true"
  }

  #setRunning(running) {
    this.busy = running
    if (running) this.#armWatchdog()
    else this.#clearWatchdog()
    // A turn that ended is no longer stopping, however it ended.
    if (!running) this.stopping = false
    this.#syncButtons()
  }

  // Stop cannot be acknowledged by the turn ending, because the reply job may
  // take a moment to notice. Reflecting it here is what stops the button being
  // pressed again while the first request is still in flight.
  #setStopping(stopping) {
    this.stopping = stopping
    this.#syncButtons()
  }

  #syncButtons() {
    const exhausted = this.#turnsExhausted()
    if (this.hasSendButtonTarget) {
      this.sendButtonTarget.classList.toggle("hidden", this.busy)
      this.sendButtonTarget.disabled = exhausted
    }
    if (this.hasStopButtonTarget) {
      this.stopButtonTarget.classList.toggle("hidden", !this.busy)
      this.stopButtonTarget.disabled = this.stopping
      const stopLabel = this.stopping ? this.stoppingLabelValue : this.stopLabelValue
      this.stopButtonTarget.title = stopLabel
      this.stopButtonTarget.setAttribute("aria-label", stopLabel)
    }
    if (this.hasRegenerateButtonTarget) this.regenerateButtonTarget.disabled = this.busy || exhausted
    // The advice in the hint beside it is only actionable if the control is
    // here too: below xl the chat list is behind a disclosure.
    if (this.hasNewChatButtonTarget) this.newChatButtonTarget.classList.toggle("hidden", !exhausted)
    if (!this.hasComposerTarget) return

    this.composerTarget.disabled = exhausted
    // A disabled box with the old invitation still in it reads as broken, so
    // the placeholder says why instead.
    this.composerTarget.placeholder = exhausted ? this.turnsExhaustedLabelValue : this.idlePlaceholder
  }

  #composerValue() {
    if (!this.hasComposerTarget) return ""
    return this.composerTarget.value.trim()
  }

  #setComposer(value) {
    if (!this.hasComposerTarget) return
    this.composerTarget.value = value
    this.resize()
  }

  // Sending is not the end of the conversation, so the caret goes back where
  // the next message gets written.
  #focusComposer() {
    if (!this.hasComposerTarget) return

    this.composerTarget.focus()
  }

  // --- `@` mentions -------------------------------------------------------
  //
  // The list is fetched rather than embedded in the page because the
  // assistant creates entities mid-thread, so a page-load snapshot would be
  // missing exactly the entity the admin just asked for.

  // @return true when an open menu consumed the key, so Enter completes the
  // mention instead of sending a half-typed message.
  #mentionKeydown(event) {
    if (!this.mentionOpen) return false
    // Arrow keys move the caret without firing `input`, so the menu can
    // outlive the mention it belongs to. A stale menu is dropped and the key
    // does its ordinary job instead.
    if (!this.#anchorIsLive()) {
      this.#closeMentions()
      return false
    }

    if (event.key === "Escape" || event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (event.key === "Escape") this.#closeMentions()
      else this.#moveMention(event.key === "ArrowDown" ? 1 : -1)
      return true
    }
    if (event.key !== "Enter" && event.key !== "Tab") return false
    // Shift+Enter is a line break and Shift+Tab is focus moving backwards,
    // whatever the menu happens to be showing.
    if (event.shiftKey) return false
    if (!this.mentionMatches.length) return false

    event.preventDefault()
    this.#insertMention(this.mentionIndex)
    return true
  }

  async #syncMentions() {
    if (!this.#mentionQuery()) {
      this.#closeMentions()
      return
    }

    await this.#loadMentions()
    // The caret can move while the request is in flight, so the query is read
    // again rather than reused.
    const anchor = this.#mentionQuery()
    if (!anchor) {
      this.#closeMentions()
      return
    }

    this.mentionAnchor = anchor
    this.mentionMatches = this.#mentionMatchesFor(anchor.query)
    this.mentionIndex = 0
    this.#renderMentions()
  }

  // The mention being typed: the text between the last `@` and the caret,
  // provided the `@` starts a word and the text still looks like a name.
  #mentionQuery() {
    if (!this.hasComposerTarget) return null

    const caret = this.composerTarget.selectionStart
    const typed = this.composerTarget.value.slice(0, caret)
    const at = typed.lastIndexOf("@")
    if (at < 0) return null
    if (at > 0 && !/\s/.test(typed[at - 1])) return null

    const query = typed.slice(at + 1)
    if (query.length > MENTION.maxQueryLength) return null
    if (query.includes("\n")) return null
    if (query.split(" ").length > MENTION.maxQueryWords) return null

    return { at, caret, query }
  }

  async #loadMentions() {
    if (!this.mentionsUrlValue) return
    if (this.mentionsLoadedAt && Date.now() - this.mentionsLoadedAt < MENTION.ttlMs) return

    // One request at a time: keystrokes come faster than the round trip, and
    // two overlapping responses could land out of order and reinstate a list
    // the second request had already replaced.
    this.mentionsRequest = this.mentionsRequest || this.#fetchMentions()
    await this.mentionsRequest
  }

  async #fetchMentions() {
    try {
      const response = await fetch(this.mentionsUrlValue, { headers: { Accept: "application/json" } })
      if (response.ok) {
        const data = await response.json()
        this.mentions = Array.isArray(data.mentions) ? data.mentions : []
      }
    } catch {
      // Keep whatever was loaded before; the menu just shows no match.
    }
    // A refusal is worth remembering too, or every keystroke retries it.
    this.mentionsLoadedAt = Date.now()
    this.mentionsRequest = null
  }

  #mentionMatchesFor(query) {
    const needle = query.trim().toLowerCase()
    return this.mentions
      .filter((row) => !needle || `${row.name} ${row.label}`.toLowerCase().includes(needle))
      .slice(0, MENTION.maxRows)
  }

  #renderMentions() {
    if (!this.hasMentionListTarget) return

    const rows = this.mentionMatches.length
      ? this.mentionMatches.map((row, index) => this.#mentionRow(row, index))
      : [this.#mentionEmptyRow()]
    this.mentionListTarget.replaceChildren(...rows)
    this.#setMentionsOpen(true)
  }

  #mentionRow(row, index) {
    const selected = index === this.mentionIndex
    const option = document.createElement("button")
    option.type = "button"
    option.id = `${MENTION_OPTION_ID}-${index}`
    option.dataset.index = String(index)
    option.setAttribute("role", "option")
    option.setAttribute("aria-selected", String(selected))
    option.className = [
      "flex w-full items-center justify-between gap-3 rounded-md px-3 py-2 text-left text-sm transition-base hover:bg-surface-hover",
      selected ? "bg-accent-subtle text-accent-text" : ""
    ].join(" ")
    option.append(
      this.#mentionCell("truncate text-text-primary", row.label || row.name),
      this.#mentionCell("shrink-0 text-caption text-text-muted", this.mentionKindsValue[row.kind] || "")
    )
    // mousedown is suppressed by the menu container, which covers the rows, the
    // padding around them and the scrollbar alike.
    option.addEventListener("click", (event) => this.pickMention(event))

    const item = document.createElement("li")
    // The listbox owns the options, not the `li` wrappers the markup needs.
    item.setAttribute("role", "presentation")
    item.appendChild(option)
    return item
  }

  #mentionCell(className, text) {
    const cell = document.createElement("span")
    cell.className = className
    cell.textContent = text
    return cell
  }

  // An option rather than plain text: the `ul` is presentational, so a row with
  // no role of its own is not in the listbox at all and never reaches a screen
  // reader. Disabled, because there is nothing here to pick.
  #mentionEmptyRow() {
    const item = document.createElement("li")
    item.id = MENTION_EMPTY_ID
    item.setAttribute("role", "option")
    item.setAttribute("aria-disabled", "true")
    item.setAttribute("aria-selected", "false")
    item.className = "px-3 py-2 text-caption text-text-muted"
    item.textContent = this.mentionEmptyLabelValue
    return item
  }

  #moveMention(step) {
    if (!this.mentionMatches.length) return

    const count = this.mentionMatches.length
    this.mentionIndex = (this.mentionIndex + step + count) % count
    this.#renderMentions()
  }

  // The menu belongs to the mention the caret was in at the last keystroke.
  #anchorIsLive() {
    const live = this.#mentionQuery()
    if (!live) return false

    return this.#mentionAnchorKey(live) === this.#mentionAnchorKey(this.mentionAnchor)
  }

  #mentionAnchorKey({ at, query }) {
    return `${at}:${query}`
  }

  #insertMention(index) {
    const choice = this.mentionMatches[index]
    if (!choice || !this.#anchorIsLive()) return

    const { at, caret } = this.mentionAnchor
    const value = this.composerTarget.value
    const mention = `@${choice.name} `
    this.composerTarget.value = value.slice(0, at) + mention + value.slice(caret)
    this.#closeMentions()
    this.resize()
    this.composerTarget.focus()
    this.composerTarget.setSelectionRange(at + mention.length, at + mention.length)
  }

  #deferCloseMentions() {
    this.#cancelDeferredClose()
    this.mentionBlurTimer = setTimeout(() => {
      this.mentionBlurTimer = null
      this.#closeMentions()
    }, MENTION.blurMs)
  }

  #cancelDeferredClose() {
    if (!this.mentionBlurTimer) return

    clearTimeout(this.mentionBlurTimer)
    this.mentionBlurTimer = null
  }

  #closeMentions() {
    this.#cancelDeferredClose()
    this.mentionMatches = []
    this.mentionAnchor = NO_MENTION
    if (this.hasMentionListTarget) this.mentionListTarget.replaceChildren()
    this.#setMentionsOpen(false)
  }

  #setMentionsOpen(open) {
    this.mentionOpen = open
    if (this.hasMentionMenuTarget) this.mentionMenuTarget.classList.toggle("hidden", !open)
    if (!this.hasComposerTarget) return

    this.composerTarget.setAttribute("aria-expanded", String(open))
    if (!open) {
      this.composerTarget.removeAttribute("aria-activedescendant")
      return
    }

    // Pointed at the "no match" row when there is nothing to pick, so the
    // outcome of the query is read out rather than silently nothing.
    const active = this.mentionMatches.length
      ? `${MENTION_OPTION_ID}-${this.mentionIndex}`
      : MENTION_EMPTY_ID
    this.composerTarget.setAttribute("aria-activedescendant", active)
  }

  // The layout's meta tag is the only token tied to the real session; one
  // baked into this element would go stale the moment the panel is re-rendered
  // offline by a broadcast.
  #csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return (meta && meta.getAttribute("content")) || ""
  }

  #scrollToBottom() {
    if (!this.hasThreadTarget) return
    this.threadTarget.scrollTop = this.threadTarget.scrollHeight
  }

  #atBottom() {
    if (!this.hasThreadTarget) return true

    const thread = this.threadTarget
    return thread.scrollHeight - thread.scrollTop - thread.clientHeight <= PINNED_SLACK_PX
  }

  // A wheel carries its own direction. A touch drag carries only positions, so
  // the previous one is kept to work out which way the content moved — a finger
  // travelling down pulls earlier messages into view. `touchstart` seeds that
  // position, or the first move of a gesture would be measured against where
  // the last one ended.
  #readingBack(event) {
    if (typeof event?.deltaY === "number") return event.deltaY < 0

    const y = event?.touches?.[0]?.clientY
    if (typeof y !== "number") return false

    const previous = event.type === "touchstart" ? null : this.lastTouchY
    this.lastTouchY = y
    return previous !== null && y > previous
  }

  // Offered instead of yanking the viewport out from under the reader.
  #setJumpVisible(visible) {
    if (!this.hasJumpButtonTarget) return

    this.jumpButtonTarget.classList.toggle("hidden", !visible)
  }

  #lastMessage() {
    if (!this.hasThreadTarget) return null
    const nodes = this.threadTarget.querySelectorAll("[data-role]")
    return nodes.length ? nodes[nodes.length - 1] : null
  }

  #flashCopy(button, ok) {
    if (!button) return

    button.setAttribute("aria-label", ok ? this.copiedLabelValue : this.copyFailedLabelValue)
    const idle = button.querySelector("[data-copy-idle]")
    const done = button.querySelector("[data-copy-done]")
    if (idle) idle.classList.toggle("hidden", ok)
    if (done) done.classList.toggle("hidden", !ok)

    if (this.copyTimer) clearTimeout(this.copyTimer)
    this.copyTimer = setTimeout(() => this.#resetCopy(button), 1600)
  }

  #resetCopy(button) {
    this.copyTimer = null
    button.setAttribute("aria-label", this.copyLabelValue)
    const idle = button.querySelector("[data-copy-idle]")
    const done = button.querySelector("[data-copy-done]")
    if (idle) idle.classList.remove("hidden")
    if (done) done.classList.add("hidden")
  }

  #fileList() {
    return Array.isArray(this.files) ? this.files : []
  }

  #commitFiles(files) {
    const error = this.#validateFiles(files)
    this.#setError(error)
    if (!error) this.files = files
    this.#renderPreviews()
  }

  #validateFiles(files) {
    if (files.length > this.maxFilesValue) {
      return this.tooManyTemplateValue.replace("{count}", String(this.maxFilesValue))
    }
    const allowed = this.acceptValue.split(",").map((type) => type.trim()).filter(Boolean)
    let total = 0
    for (const file of files) {
      if (allowed.length && !allowed.includes(file.type)) return this.typeLabelValue
      if (file.size > this.maxBytesValue) {
        return this.sizeTemplateValue.replace("{size}", this.sizeLabelValue)
      }
      total += file.size
    }
    return total > this.maxTotalBytesValue ? this.totalSizeLabelValue : null
  }

  // One slot for every failure the composer can produce: send, regenerate,
  // stop, attachment validation and a lost connection. Only the last of those
  // is worth interrupting a reply that is still arriving for.
  #setError(error, assertive = false) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = error || ""
    this.errorTarget.classList.toggle("hidden", !error)
    this.errorTarget.setAttribute("aria-live", assertive ? "assertive" : "polite")
  }

  async #sendErrorMessage(response) {
    try {
      const data = await response.json()
      const errors = data && data.errors
      if (Array.isArray(errors) && errors.length) {
        const joined = errors.filter(Boolean).join(" ")
        if (joined) return joined
      }
      if (typeof errors === "string" && errors) return errors
    } catch {
      // Body was not JSON.
    }
    return this.sendFailedLabelValue
  }

  #renderPreviews() {
    if (!this.hasPreviewsTarget) return
    this.#revokePreviews()
    this.previewsTarget.replaceChildren()
    this.#fileList().forEach((file, index) => {
      const item = document.createElement("li")
      item.className = "flex items-center gap-2 rounded-xl bg-canvas px-2 py-1 text-xs text-text-secondary ring-1 ring-border-subtle"
      if (typeof URL !== "undefined" && URL.createObjectURL) {
        const img = document.createElement("img")
        const url = URL.createObjectURL(file)
        this.previewUrls.push(url)
        img.src = url
        img.alt = file.name
        img.className = "size-8 rounded object-cover"
        item.appendChild(img)
      }
      const name = document.createElement("span")
      name.textContent = file.name
      item.appendChild(name)
      item.appendChild(this.#removeButton(index))
      this.previewsTarget.appendChild(item)
    })
  }

  #removeButton(index) {
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.index = String(index)
    button.setAttribute("aria-label", this.removeImageLabelValue)
    button.textContent = this.removeMarkValue
    button.className = [
      "flex size-6 shrink-0 items-center justify-center rounded-full leading-none",
      "text-text-muted transition-base hover:bg-surface-active hover:text-text-primary",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent",
      "pointer-coarse:size-11"
    ].join(" ")
    button.addEventListener("click", (event) => this.removeImage(event))
    return button
  }

  #revokePreviews() {
    this.previewUrls.forEach((url) => {
      if (URL.revokeObjectURL) URL.revokeObjectURL(url)
    })
    this.previewUrls = []
  }
}
