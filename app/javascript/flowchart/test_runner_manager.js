import { getCSRFToken, escapeHtml } from "utils"
import { flowchartUrl } from "flowchart/urls"

/**
 * TestRunnerManager - Owns all Test Runner panel behavior for the flowchart editor.
 *
 * Responsibilities:
 * - Run a trace against the server (auto-save first, 15s client abort backstop)
 * - Live JSON validation of the input textarea (Run button gating)
 * - localStorage persistence of the last input per flowchart
 * - In-memory run history (newest first, capped at 10) rendered as pills
 * - Structured results rendering: status banner, per-step list with status
 *   icons + click-to-locate + ctx snapshots, SQL query summary, final
 *   context and raw trace
 *
 * The Stimulus controller passes itself in; targets are accessed through it
 * and every access is guarded with hasXTarget so older markup stays safe.
 */

const HISTORY_CAP = 10
const CLIENT_TIMEOUT_MS = 15000

export class TestRunnerManager {
  constructor(controller) {
    this.controller = controller
    this.history = []
    this.activeHistoryIndex = -1
    this.runInFlight = false
  }

  // ===================
  // Public API
  // ===================

  async run() {
    if (this.runInFlight) return
    const c = this.controller
    if (!c.idValue || !c.customerIdValue) return

    const rawInput = c.hasTestInputTarget ? c.testInputTarget.value : ""
    let input
    try {
      input = JSON.parse(rawInput.trim() || "{}")
    } catch (e) {
      // The button should already be disabled by validateInput; this is a
      // belt-and-braces guard (e.g. programmatic invocation).
      this.validateInput()
      this._displayTestError(c.testInvalidJsonInputFormatValue.replace("{message}", e.message))
      return
    }

    const tracesUrl = flowchartUrl(c, "traces")
    if (!tracesUrl) return

    // Persist the last-used input per flowchart (silent degrade in private mode)
    try {
      localStorage.setItem(this._storageKey(), rawInput)
    } catch (_e) { /* storage unavailable — non-fatal */ }

    this.runInFlight = true
    this._setRunButtonDisabled(true)
    this._setTestStatus("running", c.testRunningLabelValue)

    let abortTimer
    try {

      const abort = new AbortController()
      abortTimer = setTimeout(() => abort.abort(), CLIENT_TIMEOUT_MS)

      const response = await fetch(tracesUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCSRFToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({
          input,
          configuration: c._buildSaveConfiguration()
        }),
        signal: abort.signal
      })

      // Guard the status before parsing: a 4xx/5xx may return an HTML error
      // page, so response.json() would throw and be misreported as a network
      // error. Surface the real status instead.
      if (!response.ok) {
        let serverError = c.testServerErrorFormatValue.replace("{status}", response.status)
        try {
          const errBody = await response.json()
          if (errBody?.error) serverError = errBody.error
        } catch { /* non-JSON body; keep the status message */ }
        this._displayTestError(serverError)
        return
      }

      const data = await response.json()
      this._pushHistory(rawInput, data)
      this._displayTraceResults(data)
    } catch (error) {
      if (error.name === "AbortError") {
        this._displayTestError(c.testClientTimeoutFormatValue.replace("{seconds}", CLIENT_TIMEOUT_MS / 1000))
      } else {
        this._displayTestError(c.networkErrorFormatValue.replace("{message}", error.message))
      }
    } finally {
      clearTimeout(abortTimer)
      this.runInFlight = false
      // Re-enable the Run button according to the current textarea content.
      this.validateInput()
    }
  }

  clear() {
    this.controller.canvas?.clearTraceOverlay()
  }

  selectHistory(index) {
    const entry = this.history[index]
    if (!entry) return
    this.activeHistoryIndex = index
    this._renderHistory()
    this._displayTraceResults(entry.data)
  }

  useHistoryInput(index) {
    const entry = this.history[index]
    const c = this.controller
    if (!entry || !c.hasTestInputTarget) return
    c.testInputTarget.value = entry.input
    this.validateInput()
  }

  validateInput() {
    const c = this.controller
    if (!c.hasTestInputTarget) return true

    const raw = c.testInputTarget.value.trim()
    let message = null
    if (raw) {
      try {
        JSON.parse(raw)
      } catch (e) {
        message = c.testInvalidJsonFormatValue.replace("{message}", e.message)
      }
    }
    const invalid = message !== null

    c.testInputTarget.classList.toggle("border-red-400", invalid)
    c.testInputTarget.classList.toggle("ring-1", invalid)
    c.testInputTarget.classList.toggle("ring-red-300", invalid)

    if (c.hasTestInputErrorTarget) {
      c.testInputErrorTarget.textContent = message || ""
      c.testInputErrorTarget.classList.toggle("hidden", !invalid)
    }

    this._setRunButtonDisabled(invalid || this.runInFlight)
    return !invalid
  }

  restoreSavedInput() {
    const c = this.controller
    if (!c.hasTestInputTarget) return
    try {
      const saved = localStorage.getItem(this._storageKey())
      if (saved !== null && saved !== "") c.testInputTarget.value = saved
    } catch (_e) { /* storage unavailable — non-fatal */ }
  }

  // ===================
  // History
  // ===================

  _pushHistory(input, data) {
    const status = data.timeout ? "timeout" : (data.success ? "success" : "failure")
    this.history.unshift({ at: new Date(), status, input, data })
    if (this.history.length > HISTORY_CAP) this.history.length = HISTORY_CAP
    this.activeHistoryIndex = 0
    this._renderHistory()
  }

  _renderHistory() {
    const c = this.controller
    if (!c.hasTestHistoryTarget) return

    const timeFormat = new Intl.DateTimeFormat(c.appLocaleValue, { timeStyle: "medium" })
    c.testHistoryTarget.innerHTML = this.history.map((entry, i) => {
      const icon = { success: "✓", failure: "✕", timeout: "⏱" }[entry.status] || "•"
      const iconColor = { success: "text-green-600", failure: "text-red-600", timeout: "text-amber-600" }[entry.status] || "text-slate-500"
      const time = escapeHtml(timeFormat.format(entry.at))
      const active = i === this.activeHistoryIndex
      const pillClasses = active
        ? "border-indigo-300 bg-indigo-50 text-indigo-800"
        : "border-slate-200 bg-white text-slate-600"
      return `
        <span class="inline-flex items-center rounded-full border text-xs ${pillClasses}">
          <button type="button"
                  class="px-2 py-0.5 hover:text-slate-900"
                  data-action="click->flowchart-canvas#selectTestHistoryRun"
                  data-history-index="${i}"
                  title="${escapeHtml(c.testHistoryViewTitleValue)}">${time} <span class="${iconColor}">${icon}</span></button>
          <button type="button"
                  class="pr-2 text-[10px] underline text-slate-400 hover:text-slate-600"
                  data-action="click->flowchart-canvas#loadTestHistoryInput"
                  data-history-index="${i}"
                  title="${escapeHtml(c.testHistoryUseInputTitleValue)}">${escapeHtml(c.testUseInputLabelValue)}</button>
        </span>`
    }).join("")
  }

  // ===================
  // Rendering
  // ===================

  _displayTraceResults(data) {
    const c = this.controller

    // Always clear the previous run's overlay first. Otherwise a run that
    // returns no trace_nodes (or a later error) leaves stale highlights from
    // an earlier successful run on the canvas, misrepresenting this result.
    this.clear()

    // Status badge
    if (data.timeout) {
      this._setTestStatus("timeout", c.testTimedOutLabelValue)
    } else if (data.success) {
      this._setTestStatus("success", c.testSuccessFormatValue.replace("{signal}", data.signal || c.testCompletedFallbackValue))
    } else {
      this._setTestStatus("failure", data.error || c.testExecutionFailedLabelValue)
    }

    let outputHtml = this._renderBanner(data)
    outputHtml += this._renderSteps(data)
    outputHtml += this._renderQueries(data)

    // Final context output (existing treatment)
    if (data.context && Object.keys(data.context).length > 0) {
      outputHtml += `<div class="mb-2">`
      outputHtml += `<div class="text-slate-500 font-medium mb-1">${escapeHtml(c.testContextLabelValue)}</div>`
      outputHtml += `<pre class="whitespace-pre-wrap break-all text-slate-800 bg-white border border-slate-200 rounded p-1.5">${escapeHtml(JSON.stringify(data.context, null, 2))}</pre>`
      outputHtml += `</div>`
    }

    // Raw trace output (collapsible, existing treatment)
    if (data.trace) {
      outputHtml += `<details class="mb-2">`
      outputHtml += `<summary class="text-slate-500 font-medium cursor-pointer hover:text-slate-700">${escapeHtml(c.testTraceOutputLabelValue)}</summary>`
      outputHtml += `<pre class="mt-1 whitespace-pre-wrap break-all text-slate-700 bg-white border border-slate-200 rounded p-1.5">${escapeHtml(data.trace)}</pre>`
      outputHtml += `</details>`
    }

    if (c.hasTestOutputTarget) {
      c.testOutputTarget.innerHTML = outputHtml
      const failing = c.testOutputTarget.querySelector("[data-trace-failing]")
      if (failing) failing.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }

    // Apply trace overlay on canvas. On timeout, steps completed before the
    // cutoff still render and overlay — the banner stays in the timeout state.
    if (data.trace_nodes && data.trace_nodes.length > 0) {
      c.canvas?.showTraceOverlay(data.trace_nodes)
    }
  }

  _renderBanner(data) {
    const c = this.controller
    if (data.timeout) {
      const text = data.error || c.testDefaultTimeoutBannerValue
      return `<div class="mb-2 px-2 py-1 rounded bg-amber-50 text-amber-800 font-medium">${escapeHtml(text)}</div>`
    }
    if (data.success) {
      return `<div class="mb-2 px-2 py-1 rounded bg-green-50 text-green-700 font-medium">${escapeHtml(c.testExecutionSucceededLabelValue)}</div>`
    }
    const errors = Array.isArray(data.errors) ? data.errors : []
    const list = errors.length === 0
      ? ""
      : `<ul class="mt-1 list-disc pl-4 text-xs font-normal">${errors.map((msg) => `<li>${escapeHtml(msg)}</li>`).join("")}</ul>`
    const detail = data.error && data.error !== c.testExecutionFailedLabelValue
      ? `: ${escapeHtml(data.error)}`
      : ""
    return `<div class="mb-2 px-2 py-1 rounded bg-red-50 text-red-700 font-medium">${escapeHtml(c.testExecutionFailedLabelValue)}${detail}${list}</div>`
  }

  _renderTruncationNotice(data) {
    const c = this.controller
    if (!data.trace_truncated) return ""
    const count = (data.trace_nodes || []).length
    const text = c.testTraceTruncatedFormatValue.replaceAll("{count}", () => String(count))
    return `<div class="mb-2 px-2 py-1 rounded bg-slate-50 text-slate-600">${escapeHtml(text)}</div>`
  }

  _renderSteps(data) {
    const c = this.controller
    const nodes = data.trace_nodes || []
    const truncation = this._renderTruncationNotice(data)
    if (nodes.length === 0) {
      const empty = data.success
        ? `<div class="mb-2 px-2 py-1 text-slate-500">${escapeHtml(c.testNoTracedStepsLabelValue)}</div>`
        : ""
      return `${truncation}${empty}`
    }

    let firstFailingMarked = false
    const rows = nodes.map((node, i) => {
      const failing = node.status === "failure" || node.status === "error"
      const resolvable = Boolean(node.element_id) &&
        Boolean(this.controller.canvas?.elements?.some(el => el.id === node.element_id))

      const icon = node.status === "success"
        ? `<span class="flex-shrink-0 text-green-600 font-bold">✓</span>`
        : (failing
          ? `<span class="flex-shrink-0 text-red-600 font-bold">✕</span>`
          : `<span class="flex-shrink-0 text-slate-400 font-bold">◦</span>`)

      const liClasses = [
        "rounded border px-1.5 py-1",
        failing ? "bg-red-50 border-red-200" : "bg-white border-slate-200"
      ].join(" ")

      const headClasses = [
        "flex items-start gap-2",
        resolvable ? "cursor-pointer hover:bg-slate-50" : "text-slate-400"
      ].join(" ")
      const headAttrs = resolvable
        ? ` data-action="click->flowchart-canvas#focusTraceStep" data-element-id="${escapeHtml(node.element_id)}"`
        : ""

      const errorInline = (failing && data.error)
        ? `<div class="mt-0.5 text-xs text-red-700">${escapeHtml(data.error)}</div>`
        : ""

      const ctxBody = node.ctx_snapshot
        ? `<pre class="mt-1 whitespace-pre-wrap break-all text-slate-700 bg-white border border-slate-200 rounded p-1.5">${escapeHtml(JSON.stringify(node.ctx_snapshot, null, 2))}</pre>`
        : `<div class="mt-1 text-slate-400 italic">${escapeHtml(c.testContextNotCapturedLabelValue)}</div>`

      const failingAttr = (failing && !firstFailingMarked) ? " data-trace-failing" : ""
      if (failing) firstFailingMarked = true

      return `
        <li class="${liClasses}"${failingAttr}>
          <div class="${headClasses}"${headAttrs}>
            <span class="flex-shrink-0 inline-flex items-center justify-center w-5 h-5 rounded-full bg-slate-800 text-white text-[10px]">${i + 1}</span>
            ${icon}
            <span class="min-w-0 break-words ${failing ? "text-red-700 font-medium" : ""}">${escapeHtml(this._stepLabel(node))}</span>
          </div>
          ${errorInline}
          <details class="ml-7 mt-0.5">
            <summary class="text-xs text-slate-400 cursor-pointer hover:text-slate-600">${escapeHtml(c.testContextToggleLabelValue)}</summary>
            ${ctxBody}
          </details>
        </li>`
    }).join("")

    return `${truncation}
      <div class="mb-2">
        <div class="text-slate-500 font-medium mb-1">${escapeHtml(c.testStepsLabelValue)}</div>
        <ol class="space-y-1">${rows}</ol>
      </div>`
  }

  _renderQueries(data) {
    const c = this.controller
    const queries = data.queries
    if (!queries || queries.length === 0) {
      return `<div class="mb-2 text-slate-500">${escapeHtml(c.testNoQueriesLabelValue)}</div>`
    }

    const total = queries.reduce((sum, q) => sum + (Number(q.duration_ms) || 0), 0)
    const summaryFormat = queries.length === 1 ? c.testQuerySummarySingularFormatValue : c.testQuerySummaryPluralFormatValue
    const summary = summaryFormat.replace("{count}", queries.length).replace("{duration}", total.toFixed(1))

    const items = queries.map(q => {
      const duration = c.testQueryDurationFormatValue
        .replaceAll("{duration}", () => (Number(q.duration_ms) || 0).toFixed(1))
      const name = q.name ? `<span class="text-slate-400">${escapeHtml(q.name)}</span> · ` : ""
      return `
        <li class="rounded border border-slate-200 bg-white px-1.5 py-1">
          <div class="text-xs">${name}<span class="text-slate-500">${escapeHtml(duration)}</span></div>
          <pre class="mt-0.5 whitespace-pre-wrap break-all font-mono text-slate-700">${escapeHtml(q.sql || "")}</pre>
        </li>`
    }).join("")

    return `
      <details class="mb-2">
        <summary class="text-slate-500 font-medium cursor-pointer hover:text-slate-700">${escapeHtml(c.testSqlQueriesLabelFormatValue.replace("{summary}", summary))}</summary>
        <ol class="mt-1 space-y-1">${items}</ol>
      </details>`
  }

  _displayTestError(message) {
    // Clear any overlay from a prior successful run so a failed run doesn't
    // leave misleading highlights on the canvas.
    this.clear()
    this._setTestStatus("failure", this.controller.testErrorLabelValue)
    if (this.controller.hasTestOutputTarget) {
      this.controller.testOutputTarget.innerHTML = `<div class="px-2 py-1 rounded bg-red-50 text-red-700 font-medium">${escapeHtml(message)}</div>`
    }
  }

  _setTestStatus(type, text) {
    const c = this.controller
    if (!c.hasTestStatusTarget) return

    c.testStatusTarget.classList.remove(
      "hidden",
      "bg-green-100", "text-green-800",
      "bg-red-100", "text-red-800",
      "bg-yellow-100", "text-yellow-800",
      "bg-amber-100", "text-amber-800"
    )

    switch (type) {
      case "success":
        c.testStatusTarget.classList.add("bg-green-100", "text-green-800")
        break
      case "failure":
        c.testStatusTarget.classList.add("bg-red-100", "text-red-800")
        break
      case "running":
        c.testStatusTarget.classList.add("bg-yellow-100", "text-yellow-800")
        break
      case "timeout":
        c.testStatusTarget.classList.add("bg-amber-100", "text-amber-800")
        break
    }

    c.testStatusTarget.classList.add("inline-flex")
    c.testStatusTarget.textContent = text
  }

  // ===================
  // Helpers
  // ===================

  _setRunButtonDisabled(disabled) {
    const c = this.controller
    if (!c.hasTestRunButtonTarget) return
    c.testRunButtonTarget.disabled = disabled
    c.testRunButtonTarget.classList.toggle("opacity-50", disabled)
    c.testRunButtonTarget.classList.toggle("cursor-not-allowed", disabled)
  }

  _storageKey() {
    return `flowchartTestInput:${this.controller.idValue}`
  }

  _stepLabel(node) {
    const c = this.controller
    const step = node.label || node.id || c.testUnnamedStepFallbackValue
    if (node.branch == null || node.branch === "") return step
    return c.testDecisionBranchFormatValue
      .replaceAll("{step}", () => step)
      .replaceAll("{branch}", () => String(node.branch))
  }
}
