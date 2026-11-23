import { BaseManager, escapeHtml } from "controllers/entity_form/base_manager"
import { resolveValidatorLabel } from "constants/validator_labels"
import { CONFIG_TYPE_MAP } from "controllers/entity_form/type_manager"

export class TemplateBuilder extends BaseManager {
  buildTableHtml() {
    return `
      <table class="w-full min-w-[860px] divide-y divide-border-subtle table-fixed" data-entity-form-target="attributesTable">
        <thead class="table-header">
          <tr>
            <th scope="col" class="w-8"></th>
            <th scope="col" class="w-6"></th>
            <th scope="col" class="w-6"></th>
            <th scope="col" class="px-3 py-2.5 text-left w-40">${escapeHtml(this.c.nameLabelValue)}</th>
            <th scope="col" class="px-3 py-2.5 text-left w-40">${escapeHtml(this.c.displayLabelHeaderValue)}</th>
            <th scope="col" class="px-3 py-2.5 text-left w-32">${escapeHtml(this.c.htmlTypeHeaderValue)}</th>
            <th scope="col" class="px-3 py-2.5 text-left w-36">${escapeHtml(this.c.validatorsHeaderValue)}</th>
            <th scope="col" class="px-3 py-2.5 text-left w-44">${escapeHtml(this.c.visibilityHeaderValue)}</th>
            <th scope="col" class="px-3 py-2.5 text-right w-28">${escapeHtml(this.c.actionsHeaderValue)}</th>
          </tr>
        </thead>
        <tbody class="bg-surface divide-y divide-border-subtle"></tbody>
      </table>
    `
  }

  buildAttributeRowHtml({ name, name_slug, display_label, html_type, description, validators, visibility, validator_apply, editable, group_id, config, type, owner }) {
    const index = this.c.attributeIndex
    const displayHtmlType = this.c.typeManager.formatHtmlTypeName(html_type)
    const validatorsJson = JSON.stringify(validators)
    const configJson = JSON.stringify(config || null)
    const validatorBadges = this.buildValidatorBadgesHtml(validators)
    const normalizedVisibility = this.c.schemaManager.normalizeVisibility(visibility)
    const normalizedEditable = this.c.schemaManager.coerceEditable(visibility, editable)
    const normalizedValidatorApply = this.c.schemaManager.coerceValidatorApply(visibility, validator_apply, normalizedEditable)
    const visibilityJson = JSON.stringify(normalizedVisibility)
    const editableJson = JSON.stringify(normalizedEditable)
    const validatorApplyJson = JSON.stringify(normalizedValidatorApply)
    const visibilityBadges = this.buildVisibilityBadgesHtml(normalizedVisibility)
    const displayLabel = display_label || name || ""
    const safeGroupId = escapeHtml(group_id || "")
    const safeType = escapeHtml(type || "")
    const ownerFlag = owner === true
    const typeBadge = type === "Computed"
      ? `<span class="ml-1 badge badge-accent" data-field="attr_type">${escapeHtml(this.c.computedTypeBadgeValue)}</span>`
      : ""

    return `
      <tr data-attribute-item class="attribute-item"
          draggable="true"
          data-action="dragstart->entity-form#dragStartRow dragover->entity-form#dragOverRow drop->entity-form#dropRow dragend->entity-form#dragEndRow"
          data-attr-name="${escapeHtml(name)}"
          data-attr-name-slug="${escapeHtml(name_slug)}"
          data-attr-display-label="${escapeHtml(displayLabel)}"
          data-attr-html-type="${escapeHtml(html_type || "")}"
          data-attr-type="${safeType}"
          data-attr-description="${escapeHtml(description)}"
          data-attr-validators="${escapeHtml(validatorsJson)}"
          data-attr-visibility="${escapeHtml(visibilityJson)}"
          data-attr-validator-apply="${escapeHtml(validatorApplyJson)}"
          data-attr-editable="${escapeHtml(editableJson)}"
          data-attr-group-id="${safeGroupId}"
          data-attr-config="${escapeHtml(configJson)}"
          data-attr-owner="${ownerFlag ? "true" : ""}">
        <td class="pl-3 pr-1 py-2 w-8"><span class="inline-block w-1 h-6 rounded bg-transparent"></span></td>
        <td class="px-1 py-2 w-6"><input type="checkbox" data-action="change->entity-form#toggleAttributeSelection" class="rounded"></td>
        <td class="px-1 py-2 w-6 cursor-grab text-text-muted" title="${escapeHtml(this.c.dragTitleValue)}">⋮⋮</td>
        <td class="px-3 py-2 text-sm font-medium text-text-primary"><span class="block truncate cursor-help" data-field="name" title="${escapeHtml(name)}">${escapeHtml(name)}</span></td>
        <td class="px-3 py-2 text-body-sm text-text-primary"><span class="block truncate cursor-help" data-field="display_label" title="${escapeHtml(displayLabel)}">${escapeHtml(displayLabel)}</span></td>
        <td class="px-3 py-2">
          <span class="badge badge-success" data-field="html_type">${escapeHtml(displayHtmlType)}</span>
          ${typeBadge}
        </td>
        <td class="px-3 py-2" data-field="validators">${validatorBadges}</td>
        <td class="px-3 py-2" data-field="visibility">${visibilityBadges}</td>
        <td class="px-3 py-2 text-right">
          <div class="inline-flex items-center justify-end gap-0.5">
            <button type="button" data-action="click->entity-form#viewAttribute" class="action-icon" title="${escapeHtml(this.c.viewAttributeTitleValue)}">
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /><path stroke-linecap="round" stroke-linejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" /></svg>
            </button>
            <button type="button" data-action="click->entity-form#copyAttribute" class="action-icon" title="${escapeHtml(this.c.copyAttributeTitleValue)}">
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" /></svg>
            </button>
            <button type="button" data-action="click->entity-form#editAttribute" class="action-icon" title="${escapeHtml(this.c.editAttributeTitleValue)}">
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" /></svg>
            </button>
            <button type="button" data-action="click->entity-form#removeAttribute" class="attribute-remove action-icon action-icon-danger" title="${escapeHtml(this.c.removeAttributeTitleValue)}">
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
            </button>
          </div>
          <input type="hidden" name="attributes[${index}][name]" value="${escapeHtml(name)}" data-input="name">
          <input type="hidden" name="attributes[${index}][name_slug]" value="${escapeHtml(name_slug)}" data-input="name_slug">
          <input type="hidden" name="attributes[${index}][display_label]" value="${escapeHtml(displayLabel)}" data-input="display_label">
          <input type="hidden" name="attributes[${index}][html_type]" value="${escapeHtml(html_type || "")}" data-input="html_type">
          <input type="hidden" name="attributes[${index}][type]" value="${safeType}" data-input="type">
          <input type="hidden" name="attributes[${index}][description]" value="${escapeHtml(description)}" data-input="description">
          <input type="hidden" name="attributes[${index}][validators]" value="${escapeHtml(validatorsJson)}" data-input="validators">
          <input type="hidden" name="attributes[${index}][visibility]" value="${escapeHtml(visibilityJson)}" data-input="visibility">
          <input type="hidden" name="attributes[${index}][validator_apply]" value="${escapeHtml(validatorApplyJson)}" data-input="validator_apply">
          <input type="hidden" name="attributes[${index}][editable]" value="${escapeHtml(editableJson)}" data-input="editable">
          <input type="hidden" name="attributes[${index}][group_id]" value="${safeGroupId}" data-input="group_id">
          <input type="hidden" name="attributes[${index}][config]" value="${escapeHtml(configJson)}" data-input="config">
          <input type="hidden" name="attributes[${index}][owner]" value="${ownerFlag ? "true" : ""}" data-input="owner">
        </td>
      </tr>
    `
  }

  buildAttributeGroupHeaderHtml(group, count) {
    const isUngrouped = !group
    const safeName = escapeHtml(isUngrouped ? this.c.groupUngroupedLabelValue : group.name)
    const colorClassFor = (color) => {
      const map = { slate: "bg-slate-500", indigo: "bg-indigo-500", sky: "bg-sky-500", teal: "bg-teal-500",
                    emerald: "bg-emerald-500", amber: "bg-amber-500", rose: "bg-rose-500", violet: "bg-violet-500" }
      return map[color] || "bg-slate-500"
    }
    const colorBar = isUngrouped
      ? '<span class="inline-block w-1 h-6 rounded bg-text-muted/30"></span>'
      : `<span class="inline-block w-1 h-6 rounded ${colorClassFor(group.color)}"></span>`
    const groupId = isUngrouped ? "" : escapeHtml(group.id)
    const descHtml = !isUngrouped && group.description
      ? `<span class="text-xs text-text-muted truncate max-w-xs">${escapeHtml(group.description)}</span>`
      : ""
    const emptyBadge = count === 0
      ? `<span class="ml-1 px-1.5 py-0.5 text-xs rounded bg-text-muted/10">${escapeHtml(this.c.groupEmptyBadgeLabelValue)}</span>`
      : ""
    const dragAttrs = isUngrouped
      ? ""
      : `draggable="true" data-action="dragstart->entity-form#dragStartGroup dragover->entity-form#dragOverGroupHeader drop->entity-form#dropGroup"`
    const kebab = isUngrouped
      ? ""
      : `<button type="button" class="ml-auto p-1 text-text-muted hover:text-text-primary"
              data-action="click->entity-form#openGroupMenu"
              data-group-id="${groupId}" title="${escapeHtml(this.c.groupActionsTitleValue)}">⋯</button>`
    const nameClass = isUngrouped
      ? "font-semibold text-sm text-text-muted"
      : "font-semibold text-sm text-text-primary"
    const rowClass = isUngrouped
      ? "bg-accent-subtle/30 select-none"
      : "bg-accent-subtle/50 select-none"

    return `
      <tr data-attribute-group-header
          data-group-id="${groupId}"
          ${dragAttrs}
          class="${rowClass}">
        <td colspan="9" class="px-3 py-2">
          <div class="flex items-center gap-2">
            ${colorBar}
            <span class="${nameClass}">${safeName}</span>
            ${descHtml}
            <span class="text-xs text-text-muted normal-case font-normal">${escapeHtml((count === 1 ? this.c.attributeCountSingularValue : this.c.attributeCountPluralValue).replace("{count}", count))}</span>
            ${emptyBadge}
            ${kebab}
          </div>
        </td>
      </tr>
    `
  }

  _visibilityItems() {
    return [
      { key: "admin", label: this.c.adminLabelValue },
      { key: "member", label: this.c.memberLabelValue },
      { key: "public", label: this.c.publicLabelValue }
    ]
  }

  buildVisibilityBadgesHtml(visibility) {
    const v = this.c.schemaManager.normalizeVisibility(visibility)
    const items = this._visibilityItems()
    const badges = items.map(item => {
      const enabled = v[item.key]
      const cls = enabled
        ? "badge badge-accent px-1.5 py-0.5 text-xs"
        : "badge badge-default px-1.5 py-0.5 text-xs line-through opacity-50"
      return `<span class="${cls}">${escapeHtml(item.label)}</span>`
    }).join("")
    return `<div class="flex flex-wrap items-center gap-1" data-field="visibility">${badges}</div>`
  }

  buildOptionRowHtml(index) {
    const htmlType = this.c.hasModalHtmlTypeTarget ? this.c.modalHtmlTypeTarget.value : "select"
    const isCheckbox = htmlType === "checkbox"
    const defaultInputType = isCheckbox ? "checkbox" : "radio"
    const defaultInputName = isCheckbox ? `option_default_${index}` : "option_default"

    return `
      <div data-option-item class="grid grid-cols-1 sm:grid-cols-[4.5rem_minmax(0,1fr)_minmax(0,1fr)_auto] gap-1.5 sm:items-center rounded-md border border-border-subtle bg-surface px-2 py-1.5">
        <label class="inline-flex items-center gap-1.5 text-xs text-text-primary cursor-pointer min-w-0 sm:justify-center">
          <input type="${defaultInputType}" name="${defaultInputName}" data-option-default aria-label="${escapeHtml(this.c.optionDefaultLabelValue)}" class="size-3.5 text-accent border-border-subtle focus:ring-accent${isCheckbox ? " rounded" : ""}">
          <span class="sm:hidden">${escapeHtml(this.c.optionDefaultLabelValue)}</span>
        </label>
        <input type="text" data-option-label data-action="input->entity-form#updateOptionValue" placeholder="${escapeHtml(this.c.optionLabelPlaceholderValue)}" class="input-field text-xs py-1 w-full min-w-0">
        <input type="text" data-option-value data-action="input->entity-form#markValueAsManuallyEdited" placeholder="${escapeHtml(this.c.optionValuePlaceholderValue)}" class="input-field text-xs py-1 w-full min-w-0">
        <button type="button" data-action="click->entity-form#removeOption" class="icon-button size-7 justify-self-end hover:text-danger hover:bg-danger-subtle" title="${escapeHtml(this.c.removeOptionTitleValue)}" aria-label="${escapeHtml(this.c.removeOptionTitleValue)}">
          <svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>
    `
  }

  buildValidatorBadgeHtml(value, label, validatorObject) {
    const shortLabel = label || resolveValidatorLabel(value, this.c.validatorLabelsValue)
    const cleaned = { ...(validatorObject || {}), type: value }
    delete cleaned.visibility
    const validatorJson = JSON.stringify(cleaned)
    return `
      <div data-validator-item data-validator-value="${escapeHtml(value)}" data-validator-object="${escapeHtml(validatorJson)}" class="inline-flex items-center gap-1 px-2 py-1 badge badge-default border border-border-subtle text-xs font-medium">
        <span title="${escapeHtml(label || value)}">${escapeHtml(shortLabel)}</span>
        <button type="button" data-action="click->entity-form#removeValidator" class="p-0.5 hover:bg-surface-active rounded transition-colors" title="${escapeHtml(this.c.removeValidatorTitleValue)}">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>
    `
  }

  buildValidatorBadgesHtml(validators) {
    if (!validators?.length) return '<span class="text-caption text-text-muted">-</span>'
    const badges = validators.map(v => {
      let displayLabel, titleText
      if (typeof v === 'string') {
        displayLabel = resolveValidatorLabel(v, this.c.validatorLabelsValue) || v; titleText = v
      } else if (v && typeof v === 'object' && v.type) {
        displayLabel = v.config
          ? this.c.validatorManager.buildValidatorLabelWithConfig(v.type, v.config)
          : resolveValidatorLabel(v.type, this.c.validatorLabelsValue)
        titleText = v.type
      } else {
        displayLabel = String(v); titleText = String(v)
      }
      return `<span class="badge badge-default border border-border-subtle px-1.5 py-0.5 text-xs" title="${escapeHtml(titleText)}">${escapeHtml(displayLabel)}</span>`
    }).join("")
    return `<div class="flex items-center gap-1 flex-wrap" data-field="validators">${badges}</div>`
  }

  buildTruncatedDescriptionHtml(description, maxLength = 40) {
    if (!description || description.trim() === "") return '<span class="text-caption text-text-muted">-</span>'
    if (description.length > maxLength) {
      const truncated = description.substring(0, maxLength) + "..."
      return `<span class="cursor-help" title="${escapeHtml(description)}">${escapeHtml(truncated)}</span>`
    }
    return `<span>${escapeHtml(description)}</span>`
  }

  // View-modal-local visibility badges — uses design tokens instead of raw palette.
  // NOT shared with buildVisibilityBadgesHtml (which drives the attribute table rows).
  _buildVisibilityBadgesForView(visibility) {
    const v = this.c.schemaManager.normalizeVisibility(visibility)
    const items = this._visibilityItems()
    return items.map(item => {
      const enabled = v[item.key]
      const cls = enabled
        ? "badge badge-accent px-1.5 py-0.5 text-xs"
        : "badge badge-default px-1.5 py-0.5 text-xs line-through opacity-50"
      return `<span class="${cls}">${escapeHtml(item.label)}</span>`
    }).join("")
  }

  // View-modal-local validator badges — uses design tokens (read-only styling).
  // NOT shared with buildValidatorBadgesHtml (which drives the attribute table rows).
  _buildValidatorBadgesForView(validators) {
    if (!validators?.length) return `<span class="text-body-sm text-text-muted">${escapeHtml(this.c.noneLabelValue)}</span>`
    const badges = validators.map(v => {
      let displayLabel
      if (typeof v === "string") {
        displayLabel = resolveValidatorLabel(v, this.c.validatorLabelsValue) || v
      } else if (v && typeof v === "object" && v.type) {
        displayLabel = v.config
          ? this.c.validatorManager.buildValidatorLabelWithConfig(v.type, v.config)
          : resolveValidatorLabel(v.type, this.c.validatorLabelsValue)
      } else {
        displayLabel = String(v)
      }
      return `<span class="badge badge-default border border-border-subtle px-2 py-0.5 text-xs">${escapeHtml(displayLabel)}</span>`
    }).join("")
    return `<div class="flex flex-wrap gap-1.5">${badges}</div>`
  }

  buildAttributeViewHtml({ name, name_slug: _name_slug, display_label, html_type, description, validators, visibility, validator_apply, editable, group_id, config }) {
    const GROUP_COLOR_BAR = {
      slate: "bg-slate-500", indigo: "bg-indigo-500", sky: "bg-sky-500",
      teal: "bg-teal-500", emerald: "bg-emerald-500", amber: "bg-amber-500",
      rose: "bg-rose-500", violet: "bg-violet-500"
    }

    // Resolve group
    const groups = this.c.schemaManager.readAttributeGroups()
    const group = groups.find(g => g.id === group_id) || null
    const groupChipHtml = group
      ? `<span class="inline-flex items-center gap-1.5">
           <span class="inline-block w-2 h-2 rounded-full ${GROUP_COLOR_BAR[group.color] || "bg-slate-500"}"></span>
           <span class="text-body-sm text-text-primary font-medium">${escapeHtml(group.name)}</span>
         </span>`
      : `<span class="text-body-sm text-text-muted">${escapeHtml(this.c.groupUngroupedLabelValue)}</span>`

    const displayHtmlType = this.c.typeManager.formatHtmlTypeName(html_type)
    const displayLabel = display_label || name || ""

    const visibilityBadges = this._buildVisibilityBadgesForView(visibility)
    const coercedEditable = this.c.schemaManager.coerceEditable(visibility, editable)
    const editableBadges = this._buildVisibilityBadgesForView(coercedEditable)
    const coercedApply = this.c.schemaManager.coerceValidatorApply(visibility, validator_apply, coercedEditable)
    const validatorApplyBadges = this._buildVisibilityBadgesForView(coercedApply)
    const configHtml = this.buildConfigViewHtml(config, html_type)
    const descriptionHtml = description
      ? `<p class="text-body-sm text-text-primary whitespace-pre-wrap">${escapeHtml(description)}</p>`
      : `<span class="text-body-sm text-text-muted italic">${escapeHtml(this.c.noDescriptionProvidedLabelValue)}</span>`

    const sectionHeading = (label) =>
      `<h4 class="text-label text-text-muted uppercase tracking-wider mb-3">${escapeHtml(label)}</h4>`

    const field = (label, valueHtml) => `
      <div>
        <dt class="text-caption text-text-muted mb-1">${escapeHtml(label)}</dt>
        <dd>${valueHtml}</dd>
      </div>`

    return `
<div class="space-y-5">
  <section>
    ${sectionHeading(this.c.identitySectionHeaderValue)}
    <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
      ${field(this.c.nameLabelValue, `<span class="text-body-sm font-semibold text-text-primary">${escapeHtml(name)}</span>`)}
      ${field(this.c.displayLabelHeaderValue, `<span class="text-body-sm text-text-primary">${escapeHtml(displayLabel)}</span>`)}
      ${field(this.c.htmlTypeHeaderValue, `<span class="badge badge-success px-2 py-0.5 text-xs">${escapeHtml(displayHtmlType)}</span>`)}
      ${field(this.c.groupHeaderValue, groupChipHtml)}
    </dl>
  </section>

  <hr class="border-border-subtle">

  <section>
    ${sectionHeading(this.c.audienceSectionHeaderValue)}
    <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
      ${field(this.c.visibleLabelValue, `<div class="flex flex-wrap gap-1.5">${visibilityBadges}</div>`)}
      ${field(this.c.editableLabelValue, `<div class="flex flex-wrap gap-1.5">${editableBadges}</div>`)}
      ${field(this.c.applyValidatorsLabelValue, `<div class="flex flex-wrap gap-1.5">${validatorApplyBadges}</div>`)}
    </dl>
  </section>

  <hr class="border-border-subtle">

  <section>
    ${sectionHeading(this.c.validationSectionHeaderValue)}
    <dl>
      ${field(this.c.validatorsHeaderValue, this._buildValidatorBadgesForView(validators))}
    </dl>
  </section>

  <hr class="border-border-subtle">

  <section>
    ${sectionHeading(this.c.detailsSectionHeaderValue)}
    <dl class="space-y-3">
      ${field(this.c.configurationHeaderValue, configHtml)}
      ${field(this.c.descriptionHeaderValue, descriptionHtml)}
    </dl>
  </section>
</div>
    `
  }

  buildConfigViewHtml(config, htmlType) {
    if (!config) return `<span class="text-body-sm text-text-muted">${escapeHtml(this.c.noneLabelValue)}</span>`
    const configType = CONFIG_TYPE_MAP[htmlType]
    if (configType === "selection" && config.options?.length) {
      const rows = config.options.map(opt => `
        <tr class="bg-surface">
          <td class="px-3 py-2 text-body-sm text-text-primary">${escapeHtml(opt.label || "")}</td>
          <td class="px-3 py-2"><code class="font-mono text-xs text-accent bg-accent-subtle px-1.5 py-0.5 rounded">${escapeHtml(opt.value || "")}</code></td>
          <td class="px-3 py-2">${opt.default ? `<span class="badge badge-accent px-1.5 py-0.5 text-xs">${escapeHtml(this.c.optionDefaultLabelValue)}</span>` : ""}</td>
        </tr>
      `).join("")
      return `
<div class="overflow-hidden rounded-lg border border-border-subtle">
  <table class="w-full text-xs">
    <thead>
      <tr class="bg-canvas-elevated border-b border-border-subtle">
        <th class="px-3 py-2 text-left text-label text-text-muted uppercase tracking-wider">${escapeHtml(this.c.configLabelHeaderValue)}</th>
        <th class="px-3 py-2 text-left text-label text-text-muted uppercase tracking-wider">${escapeHtml(this.c.configValueHeaderValue)}</th>
        <th class="px-3 py-2 text-left text-label text-text-muted uppercase tracking-wider">${escapeHtml(this.c.optionDefaultLabelValue)}</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-border-subtle">${rows}</tbody>
  </table>
</div>`
    }
    if (configType === "file") {
      const hasParts = config.accept || config.multiple
      if (!hasParts) return `<span class="text-body-sm text-text-muted">${escapeHtml(this.c.noneLabelValue)}</span>`
      return `
<div class="flex flex-wrap gap-3">
  ${config.accept ? `<div class="text-body-sm text-text-primary"><span class="text-text-muted">${escapeHtml(this.c.configAcceptLabelValue)}</span>${escapeHtml(config.accept)}</div>` : ""}
  <div class="text-body-sm text-text-primary"><span class="text-text-muted">${escapeHtml(this.c.configMultipleLabelValue)}</span>${config.multiple ? escapeHtml(this.c.yesLabelValue) : escapeHtml(this.c.noLabelValue)}</div>
</div>`
    }
    return `<span class="text-body-sm text-text-muted">${escapeHtml(this.c.noneLabelValue)}</span>`
  }

  buildAssociationAttributeDisplayHtml(attribute, index) {
    const displayHtmlType = this.c.typeManager.formatHtmlTypeName(attribute.html_type)
    const validatorBadges = this.buildValidatorBadgesHtml(attribute.validators || [])
    return `
      <tr data-association-attribute-item data-index="${index}" class="table-row">
        <td class="px-2 py-2"><span class="text-xs font-medium text-text-primary">${escapeHtml(attribute.name)}</span></td>
        <td class="px-2 py-2"><span class="badge badge-success">${escapeHtml(displayHtmlType)}</span></td>
        <td class="px-2 py-2"><div class="flex flex-wrap gap-1">${validatorBadges}</div></td>
        <td class="px-2 py-2 text-right">
          <div class="inline-flex items-center gap-1">
            <button type="button" data-action="click->entity-form#editAssociationAttribute" data-index="${index}" class="action-icon" title="${escapeHtml(this.c.editAttributeTitleValue)}">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" /></svg>
            </button>
            <button type="button" data-action="click->entity-form#removeAssociationAttributeFromList" data-index="${index}" class="action-icon action-icon-danger" title="${escapeHtml(this.c.removeAttributeTitleValue)}">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
            </button>
          </div>
        </td>
      </tr>
    `
  }

  buildAssociationRowHtml(association) {
    const additionalAttrs = association.additional_attributes || []
    const additionalAttrsHtml = additionalAttrs.length > 0
      ? additionalAttrs.slice(0, 3).map(attr => `<span class="badge badge-default">${escapeHtml(attr.name)}</span>`).join(" ")
      : `<span class="text-caption">${escapeHtml(this.c.noneLabelValue)}</span>`
    const moreAttrs = additionalAttrs.length > 3
      ? `<span class="text-caption">${escapeHtml(this.c.assocMoreFormatValue.replace("{count}", additionalAttrs.length - 3))}</span>`
      : ''
    const bridgeName = association.bridge_entity_name || this.c.assocWillBeCreatedLabelValue
    const bridgeClass = association.bridge_entity_name
      ? "badge badge-primary"
      : "text-caption text-warning"
    const displayFieldHtml = association.display_field_label
      ? `<code class="text-mono text-xs text-accent bg-surface-active px-1.5 py-0.5 rounded">${escapeHtml(association.display_field_label)}</code>`
      : '<span class="text-caption">-</span>'
    return `
      <tr class="table-row" data-association-item data-association-data="${escapeHtml(JSON.stringify(association))}">
        <td class="px-3 py-2"><span class="text-body text-text-primary font-medium">${escapeHtml(association.target_entity_name)}</span></td>
        <td class="px-3 py-2">${displayFieldHtml}</td>
        <td class="px-3 py-2"><span class="${bridgeClass}">${association.bridge_entity_name ? '<svg class="size-3 mr-1 inline" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" /></svg>' : ''}${bridgeName}</span></td>
        <td class="px-3 py-2"><div class="flex flex-wrap gap-1">${additionalAttrsHtml}${moreAttrs}</div></td>
        <td class="px-3 py-2 text-right">
          <div class="inline-flex items-center gap-1">
            <button type="button" data-action="click->entity-form#editAssociation" class="action-icon" title="${escapeHtml(this.c.editAssociationTitleValue)}">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" /></svg>
            </button>
            <button type="button" data-action="click->entity-form#removeAssociation" class="action-icon action-icon-danger" title="${escapeHtml(this.c.removeAssociationTitleValue)}">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
            </button>
          </div>
        </td>
      </tr>
    `
  }
}
