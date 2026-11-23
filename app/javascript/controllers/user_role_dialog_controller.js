import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    userId: Number,
    userName: String,
    currentRoleIds: Array,
    roles: Array,
    submitUrl: String,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting button (user_roles_table_component.
    // html.erb) supplies translated strings via
    // data-user-role-dialog-<name>-value="<%= t(...) %>". ──
    systemBadgeLabel: { type: String, default: "System" },
    dialogTitleLabel: { type: String, default: "Edit roles" },
    noRolesDefinedLabel: { type: String, default: "No roles defined." },
    cancelLabel: { type: String, default: "Cancel" },
    saveLabel: { type: String, default: "Save" },
    saveFailedFormat: { type: String, default: "Save failed: {details}" },
  }

  open() {
    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
    overlay.setAttribute("role", "dialog")
    overlay.setAttribute("aria-modal", "true")

    const rolesHtml = this.rolesValue.map(r => {
      const checked = this.currentRoleIdsValue.includes(r.id) ? "checked" : ""
      const desc = r.description ? `<p class="mt-0.5 text-caption">${this.esc(r.description)}</p>` : ""
      const badge = r.system
        ? `<span class="badge badge-accent px-1.5 py-0.5 ml-2 text-xs">${this.systemBadgeLabelValue}</span>`
        : ""
      return `
        <label class="flex items-start gap-3 p-3 rounded-md border border-border-subtle hover:bg-surface-hover cursor-pointer transition-base">
          <input type="checkbox" value="${r.id}" ${checked}
                 class="mt-0.5 h-4 w-4 rounded border-border-strong text-accent focus:ring-2 focus:ring-accent focus:ring-offset-0">
          <div class="flex-1 min-w-0">
            <div class="flex flex-wrap items-center gap-1">
              <span class="text-sm font-medium text-text-primary break-words">${this.esc(r.name)}</span>${badge}
            </div>
            ${desc}
          </div>
        </label>
      `
    }).join("")

    overlay.innerHTML = `
      <div class="card w-full max-w-lg max-h-[85vh] shadow-2xl flex flex-col">
        <div class="px-6 py-4 border-b border-border-subtle">
          <h2 id="user-access-dialog-title" class="text-subtitle">${this.dialogTitleLabelValue}</h2>
          <p class="mt-1 text-body-sm break-words">${this.esc(this.userNameValue)}</p>
        </div>

        <div class="flex-1 overflow-y-auto p-6 space-y-2">
          ${rolesHtml || `<p class="text-body-sm">${this.noRolesDefinedLabelValue}</p>`}
        </div>

        <div class="px-6 py-4 border-t border-border-subtle flex items-center justify-end gap-2 bg-surface">
          <button type="button" data-action="cancel" class="btn btn-secondary">${this.cancelLabelValue}</button>
          <button type="button" data-action="save" class="btn btn-primary">${this.saveLabelValue}</button>
        </div>
      </div>
    `
    document.body.appendChild(overlay)
    overlay.setAttribute("aria-labelledby", "user-access-dialog-title")

    const close = () => overlay.remove()
    overlay.addEventListener("click", (e) => { if (e.target === overlay) close() })
    overlay.querySelector('[data-action="cancel"]').addEventListener("click", close)
    document.addEventListener("keydown", function escListener(e) {
      if (e.key === "Escape") { close(); document.removeEventListener("keydown", escListener) }
    })

    overlay.querySelector('[data-action="save"]').addEventListener("click", async () => {
      const ids = [...overlay.querySelectorAll('input[type="checkbox"]:checked')].map(cb => Number(cb.value))
      const token = document.querySelector('meta[name="csrf-token"]').content
      const res = await fetch(this.submitUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token, "Accept": "application/json" },
        body: JSON.stringify({ user_id: this.userIdValue, role_ids: ids })
      })
      if (res.ok) {
        window.location.reload()
      } else {
        const err = await res.json().catch(() => ({}))
        alert(this.saveFailedFormatValue.replace("{details}", JSON.stringify(err.errors || err)))
      }
    })
  }

  esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
