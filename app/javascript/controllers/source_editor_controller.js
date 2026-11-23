import { Controller } from "@hotwired/stimulus"

const INDENT = "  "
// A line that opens a Ruby block: the next line is indented one level deeper.
const OPENS_BLOCK = /(\bdo\b(\s*\|[^|]*\|)?|[({[])\s*$|^\s*(def|class|module|if|unless|else|elsif|when|case|begin|rescue|ensure|while|until)\b/

// Plain-textarea Ruby editor: keeps the line-number gutter in sync, indents
// with two spaces (Tab / Shift+Tab, auto-indent on Enter) and submits the
// enclosing form on Ctrl/Cmd+S.
export default class extends Controller {
  static targets = ["input", "gutter"]

  connect() {
    this.refresh()
  }

  refresh() {
    const count = this.inputTarget.value.split("\n").length
    this.gutterTarget.textContent = Array.from({ length: count }, (_, index) => index + 1).join("\n")
    this.sync()
  }

  sync() {
    this.gutterTarget.scrollTop = this.inputTarget.scrollTop
  }

  save(event) {
    if (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== "s") return

    event.preventDefault()
    this.inputTarget.form?.requestSubmit()
  }

  keydown(event) {
    if (event.key === "Tab" && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault()
      event.shiftKey ? this.outdent() : this.indent()
    } else if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      this.newline()
    }
  }

  indent() {
    const { selectionStart: start, selectionEnd: end } = this.inputTarget
    if (start === end) {
      this.replace(start, end, INDENT, start + INDENT.length, start + INDENT.length)
      return
    }
    const block = this.lineBlock(start, end)
    const lines = block.text.split("\n")
    this.replace(block.start, block.end, lines.map((line) => INDENT + line).join("\n"),
      start + INDENT.length, end + INDENT.length * lines.length)
  }

  outdent() {
    const { selectionStart: start, selectionEnd: end } = this.inputTarget
    const block = this.lineBlock(start, end)
    const lines = block.text.split("\n")
    const removed = lines.map((line) => line.match(/^ {0,2}/)[0].length)
    const firstRemoved = Math.min(removed[0], start - block.start)
    const totalRemoved = removed.reduce((sum, count) => sum + count, 0)
    this.replace(block.start, block.end, lines.map((line, index) => line.slice(removed[index])).join("\n"),
      start - firstRemoved, Math.max(start - firstRemoved, end - totalRemoved))
  }

  newline() {
    const { value, selectionStart: start, selectionEnd: end } = this.inputTarget
    const lineStart = value.lastIndexOf("\n", start - 1) + 1
    const before = value.slice(lineStart, start)
    let indent = before.match(/^ */)[0]
    if (OPENS_BLOCK.test(before)) indent += INDENT
    const text = `\n${indent}`
    this.replace(start, end, text, start + text.length, start + text.length)
  }

  // The full lines touched by the selection [start, end).
  lineBlock(start, end) {
    const value = this.inputTarget.value
    const blockStart = value.lastIndexOf("\n", start - 1) + 1
    const lastChar = end > start && value[end - 1] === "\n" ? end - 1 : end
    const newline = value.indexOf("\n", lastChar)
    const blockEnd = newline === -1 ? value.length : newline
    return { start: blockStart, end: blockEnd, text: value.slice(blockStart, blockEnd) }
  }

  // Prefer insertText so the browser keeps the edit on its undo stack.
  replace(start, end, text, selectionStart, selectionEnd) {
    const input = this.inputTarget
    input.focus()
    input.setSelectionRange(start, end)
    const inserted = typeof document.execCommand === "function" && document.execCommand("insertText", false, text)
    if (!inserted) {
      input.setRangeText(text, start, end, "end")
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    input.setSelectionRange(selectionStart, selectionEnd)
  }
}
