# Email Module Implementation Plan - Phase 4: Rich Editors

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add rich editing capabilities for email templates - code editor with syntax highlighting for HTML, and a visual preview panel.

**Architecture:** StimulusJS controllers for editor interactions, CodeMirror 6 for syntax highlighting, live preview via iframe srcdoc.

**Tech Stack:** Rails 8.1, StimulusJS, CodeMirror 6 (via CDN), TailwindCSS

---

## File Structure

```
app/javascript/controllers/
├── code_editor_controller.js      # CodeMirror wrapper
├── template_preview_controller.js # Live preview sync

app/views/email/admin/templates/
├── _form.html.erb                 # Update with editor components
```

---

### Task 1: Add CodeMirror 6 via CDN

**Files:**
- Modify: `app/views/layouts/application.html.erb` or create importmap entry

Add CodeMirror 6 core + HTML/CSS language support via CDN in the head section or via importmap.

---

### Task 2: Create Code Editor Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/code_editor_controller.js`

```javascript
// app/javascript/controllers/code_editor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "editor"]
  static values = { language: { type: String, default: "html" } }

  connect() {
    this.loadCodeMirror()
  }

  async loadCodeMirror() {
    // Dynamic import from CDN
    const { EditorView, basicSetup } = await import("https://esm.sh/@codemirror/basic-setup@0.20.0")
    const { html } = await import("https://esm.sh/@codemirror/lang-html@6.4.0")
    const { EditorState } = await import("https://esm.sh/@codemirror/state@6.2.0")

    const updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        this.textareaTarget.value = update.state.doc.toString()
        this.dispatch("change", { detail: { content: this.textareaTarget.value } })
      }
    })

    this.editor = new EditorView({
      state: EditorState.create({
        doc: this.textareaTarget.value,
        extensions: [basicSetup, html(), updateListener]
      }),
      parent: this.editorTarget
    })

    this.textareaTarget.style.display = "none"
  }

  disconnect() {
    if (this.editor) {
      this.editor.destroy()
    }
  }
}
```

---

### Task 3: Create Template Preview Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/template_preview_controller.js`

```javascript
// app/javascript/controllers/template_preview_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["iframe", "source"]

  connect() {
    this.updatePreview()
  }

  updatePreview() {
    const content = this.sourceTarget.value
    this.iframeTarget.srcdoc = content
  }

  sourceChanged(event) {
    this.sourceTarget.value = event.detail.content
    this.updatePreview()
  }
}
```

---

### Task 4: Update Email Template Form with Editor

**Files:**
- Modify: `app/views/email/admin/templates/_form.html.erb`

Replace the plain textarea for body_html with:

```erb
<div data-controller="template-preview">
  <div class="grid grid-cols-2 gap-4">
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">HTML Body</label>
      <div data-controller="code-editor"
           data-action="code-editor:change->template-preview#sourceChanged"
           class="border border-gray-300 rounded-md overflow-hidden">
        <%= f.text_area :body_html,
              data: { code_editor_target: "textarea", template_preview_target: "source" },
              rows: 15,
              class: "hidden" %>
        <div data-code-editor-target="editor" class="min-h-[400px]"></div>
      </div>
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Preview</label>
      <iframe data-template-preview-target="iframe"
              class="w-full min-h-[400px] border border-gray-300 rounded-md bg-white"></iframe>
    </div>
  </div>
</div>
```

---

### Task 5: Register Stimulus Controllers

**Files:**
- Modify: `app/javascript/controllers/index.js`

Add imports and register the new controllers.

---

### Task 6: Test the Editor

- Start dev server
- Navigate to email templates new/edit page
- Verify CodeMirror loads with syntax highlighting
- Verify live preview updates as you type
- Verify form submission saves the content correctly

---

### Task 7: Commit

```bash
git add app/javascript/controllers/ app/views/email/admin/templates/_form.html.erb
git commit -m "feat(email): add code editor with syntax highlighting and live preview"
```

---

## Phase 4 Complete

Rich editing for email templates:
- CodeMirror 6 for HTML syntax highlighting
- Live preview panel that updates as you type
- Split-pane layout for editing and preview side by side

Phase 5 will integrate email sending into flowchart steps.
