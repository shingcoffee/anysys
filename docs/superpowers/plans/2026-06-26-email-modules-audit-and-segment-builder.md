# Email Modules Audit + Grouped Segment Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix verified bugs across the emails & email_campaigns modules and replace the flat segment builder with a grouped (nested AND/OR) builder modeled on the flowchart Decision condition builder.

**Architecture:** `segment_rules` becomes a recursive group `{type:"group", match:"all"|"any", conditions:[leaf|group...]}`. `AudienceQuery` compiles it recursively to tenant-scoped Arel. The `SegmentBuilderComponent` + `segment-builder` Stimulus controller render/serialize the tree. Old flat shapes are normalized on read (no data migration). Bug fixes are surgical per-file.

**Tech Stack:** Rails 8.1, Arel, ViewComponent, StimulusJS, Tailwind, RSpec.

**Test command convention:** `bundle exec rspec <path>` (single-process — never run concurrently per repo memory).

---

## Task 1: AudienceQuery — recursive groups + date/blank bug fixes (B2, B3)

**Files:**
- Modify: `app/services/email_campaigns/audience_query.rb`
- Test: `spec/services/email_campaigns/audience_query_spec.rb`

- [ ] **Step 1: Add failing tests** for nested groups, mixed AND/OR via nesting, dropped-on-bad-date, and string blank/present. Append to the existing spec:

```ruby
  it "compiles a nested group (AND of OR)" do
    admin  = create(:user, :admin,  customer: customer, first_name: "Ada")
    owner_ish = create(:user, :member, customer: customer, first_name: "Ada")
    bob    = create(:user, :admin,  customer: customer, first_name: "Bob")
    rules = {
      "type" => "group", "match" => "all",
      "conditions" => [
        { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
        { "type" => "group", "match" => "any", "conditions" => [
          { "field" => "roles.key", "operator" => "equals", "value" => "admin" },
          { "field" => "roles.key", "operator" => "equals", "value" => "owner" }
        ] }
      ]
    }
    result = query(rules).to_a
    expect(result).to include(admin)
    expect(result).not_to include(bob)      # wrong first_name
    expect(result).not_to include(owner_ish) # member, not admin/owner
  end

  it "still understands the legacy flat shape" do
    match = create(:user, customer: customer, first_name: "Ada")
    create(:user, customer: customer, first_name: "Bob")
    rules = { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] }
    expect(query(rules).to_a).to eq([match])
  end

  it "drops an 'after' condition whose value is unparseable (does not match nobody)" do
    u = create(:user, customer: customer, first_name: "Ada")
    rules = { "match" => "all", "conditions" => [
      { "field" => "created_at", "operator" => "after", "value" => "not-a-date" }
    ] }
    expect(query(rules).to_a).to include(u) # condition dropped → all users
  end

  it "treats empty-string as blank for string is_blank" do
    blank = create(:user, customer: customer, last_name: "")
    present = create(:user, customer: customer, last_name: "Lovelace")
    rules = { "match" => "all", "conditions" => [
      { "field" => "last_name", "operator" => "is_blank", "value" => "" }
    ] }
    result = query(rules).to_a
    expect(result).to include(blank)
    expect(result).not_to include(present)
  end
```

- [ ] **Step 2: Run** `bundle exec rspec spec/services/email_campaigns/audience_query_spec.rb` — expect the 4 new examples to FAIL.

- [ ] **Step 3: Rewrite `audience_query.rb`** to compile recursively. Replace the body from `def relation` through `sanitize_like`:

```ruby
    def relation
      rel = Authentication::User.for_customer(@customer.id)
      root = normalize_group(@rules)
      predicate = compile_group(root)
      return rel if predicate.nil?

      rel = apply_joins(rel)
      rel.where(predicate).distinct
    end

    def count
      relation.count
    end

    private

    attr_reader :customer, :rules, :catalog

    # Normalize legacy flat rules ({match, conditions:[leaf]}) and bare groups
    # into the canonical recursive group: {type:"group", match:, conditions:[]}.
    def normalize_group(node)
      node = (node || {}).with_indifferent_access
      {
        "match"      => node["match"].to_s == "any" ? "any" : "all",
        "conditions" => Array(node["conditions"])
      }
    end

    # Returns an Arel predicate for a group, or nil if it contributes nothing.
    def compile_group(group)
      any = group["match"].to_s == "any"
      nodes = Array(group["conditions"]).filter_map { |m| compile_member(m) }
      return nil if nodes.empty?
      nodes.reduce { |acc, n| any ? acc.or(n) : acc.and(n) }
    end

    def group?(member)
      member.is_a?(Hash) && (member["type"] || member[:type]).to_s == "group" ||
        member.is_a?(Hash) && (member.key?("conditions") || member.key?(:conditions))
    end

    def compile_member(member)
      member = member.with_indifferent_access if member.is_a?(Hash)
      return nil unless member.is_a?(Hash)
      return compile_group(member) if member["type"].to_s == "group" || member.key?("conditions")
      compile_leaf(member)
    end

    def compile_leaf(cond)
      resolved = catalog.resolve(cond["field"])
      return nil unless resolved
      predicate_for(resolved, cond["operator"].to_s, cond["value"])
    end

    def joins_in(group, acc = [])
      Array(group["conditions"]).each do |m|
        m = m.with_indifferent_access if m.is_a?(Hash)
        next unless m.is_a?(Hash)
        if m["type"].to_s == "group" || m.key?("conditions")
          joins_in(m, acc)
        else
          resolved = catalog.resolve(m["field"])
          acc << resolved[:association] if resolved && resolved[:association]
        end
      end
      acc
    end

    def apply_joins(rel)
      assocs = joins_in(normalize_group(@rules)).compact.uniq
      assocs.any? ? rel.left_outer_joins(*assocs) : rel
    end

    def arel_column(resolved)
      klass = if resolved[:association]
                Authentication::User.reflect_on_association(resolved[:association]).klass
              else
                Authentication::User
              end
      klass.arel_table[resolved[:column]]
    end

    def predicate_for(resolved, operator, value)
      col    = arel_column(resolved)
      type   = resolved[:type]

      case operator
      when "equals"       then col.eq(cast_value(type, value))
      when "not_equals"   then col.not_eq(cast_value(type, value))
      when "contains"     then col.matches("%#{sanitize_like(value)}%")
      when "not_contains" then col.does_not_match("%#{sanitize_like(value)}%")
      when "greater_than" then col.gt(cast_value(type, value))
      when "less_than"    then col.lt(cast_value(type, value))
      when "after"
        t = parse_time(value)
        t ? col.gt(t) : nil
      when "before"
        t = parse_time(value)
        t ? col.lt(t) : nil
      when "is_blank"
        string_type?(type) ? col.eq(nil).or(col.eq("")) : col.eq(nil)
      when "is_present"
        string_type?(type) ? col.not_eq(nil).and(col.not_eq("")) : col.not_eq(nil)
      else nil
      end
    end

    def string_type?(type)
      type == :string
    end

    def cast_value(type, value)
      case type
      when :integer         then value.to_i
      when :float           then value.to_f
      when :boolean         then ActiveModel::Type::Boolean.new.cast(value)
      when :datetime, :date then parse_time(value)
      else value.to_s
      end
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def sanitize_like(value)
      value.to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }
    end
```

Keep the class/module wrapper, `self.call`, and `initialize` as they are.

- [ ] **Step 4: Run** `bundle exec rspec spec/services/email_campaigns/audience_query_spec.rb` — expect PASS (all examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/email_campaigns/audience_query.rb spec/services/email_campaigns/audience_query_spec.rb
git commit -m "fix(email_campaigns): recursive segment groups + date/blank predicate fixes"
```

---

## Task 2: SegmentBuilderComponent — grouped UI, remove Advanced (Part 2 + Part 3 server side)

**Files:**
- Modify: `app/components/email_campaigns/segment_builder_component.rb`
- Modify: `app/components/email_campaigns/segment_builder_component.html.erb`
- Test: `spec/components/email_campaigns/segment_builder_component_spec.rb`

- [ ] **Step 1: Update the component spec.** Replace the "Advanced raw JSON" expectation and add group expectations. In `spec/components/email_campaigns/segment_builder_component_spec.rb`:
  - Delete the example `"includes the Advanced raw JSON collapsible with a raw textarea"`.
  - Delete the example `"populates the raw JSON textarea with pretty-printed rules"`.
  - Add to the "new list" block:

```ruby
    it "does NOT render an Advanced raw JSON section" do
      expect(rendered_content).not_to include("Advanced")
      expect(rendered_content).not_to include("data-segment-builder-target=\"raw\"")
    end

    it "renders a root group container" do
      expect(rendered_content).to include("data-segment-builder-target=\"groupRoot\"")
    end

    it "renders an Add group control" do
      expect(rendered_content).to include("Add group")
    end

    it "provides a group template for nested groups" do
      expect(rendered_content).to include("data-segment-builder-target=\"groupTemplate\"")
    end
```

- [ ] **Step 2: Run** `bundle exec rspec spec/components/email_campaigns/segment_builder_component_spec.rb` — expect new examples to FAIL.

- [ ] **Step 3: Rewrite the component class** `segment_builder_component.rb`. The component now renders a recursive tree. Keep `fields`, `operators_for`, `operator_label`, `fields_value_json`; replace the rules accessors with a normalized root group:

```ruby
# frozen_string_literal: true

module EmailCampaigns
  # Renders a grouped (nested AND/OR) condition builder for an email list's
  # segment rules, modeled on the flowchart Decision condition builder.
  #
  # segment_rules canonical shape (recursive):
  #   { "type" => "group", "match" => "all"|"any",
  #     "conditions" => [ leaf | group, ... ] }
  #   leaf: { "field" =>, "operator" =>, "value" => }
  #
  # The component pre-renders the tree server-side (usable without JS); the
  # `segment-builder` Stimulus controller keeps the hidden JSON output in sync.
  class SegmentBuilderComponent < ViewComponent::Base
    def initialize(list:, catalog: EmailCampaigns::FieldCatalog.new)
      @list    = list
      @catalog = catalog
    end

    attr_reader :list, :catalog

    def fields
      catalog.fields
    end

    # Normalized root group from list.segment_rules (handles legacy flat shape).
    def root_group
      @root_group ||= normalize(list.segment_rules)
    end

    def output_json
      JSON.generate(root_group)
    end

    def operators_for(field_id)
      entry = fields.find { |f| f[:field] == field_id }
      entry ? entry[:operators] : EmailCampaigns::FieldCatalog::OPERATORS_BY_TYPE[:string]
    end

    def fields_value_json
      map = fields.each_with_object({}) do |f, h|
        h[f[:field]] = { label: f[:label], operators: f[:operators] }
      end
      JSON.generate(map)
    end

    def operator_label(op)
      op.to_s.tr("_", " ").capitalize
    end

    # True when the member hash is a nested group.
    def group?(member)
      member.is_a?(Hash) && (member["type"].to_s == "group" || member.key?("conditions"))
    end

    private

    def normalize(node)
      node = (node || {})
      node = node.deep_stringify_keys if node.respond_to?(:deep_stringify_keys)
      {
        "type"       => "group",
        "match"      => node["match"].to_s == "any" ? "any" : "all",
        "conditions" => Array(node["conditions"]).map { |m| normalize_member(m) }
      }
    end

    def normalize_member(m)
      return { "field" => "", "operator" => "", "value" => "" } unless m.is_a?(Hash)
      m = m.deep_stringify_keys
      if m["type"].to_s == "group" || m.key?("conditions")
        normalize(m)
      else
        { "field" => m["field"].to_s, "operator" => m["operator"].to_s, "value" => m["value"].to_s }
      end
    end
  end
end
```

- [ ] **Step 4: Rewrite the template** `segment_builder_component.html.erb`. Render the root group via a recursive partial-less inline approach using the component's helpers. Replace the whole file:

```erb
<%#
  Grouped segment builder. The root group is pre-rendered server-side; the
  `segment-builder` Stimulus controller hydrates, adds/removes rows & nested
  groups, and serializes the recursive tree to the hidden output input.

  Targets:
    output        — hidden input with serialized segment_rules JSON (submitted)
    groupRoot     — the root <div data-sb-group>
    rowTemplate   — <template> cloned for a new condition row
    groupTemplate — <template> cloned for a new nested group
%>
<div data-controller="segment-builder"
     data-segment-builder-fields-value="<%= fields_value_json %>"
     class="space-y-3">

  <input type="hidden"
         name="email_list[segment_rules_json]"
         value="<%= output_json %>"
         data-segment-builder-target="output"
         aria-label="Segment rules JSON">

  <%# ── Root group (pre-rendered tree) ── %>
  <%= render_group(root_group, root: true) %>

  <%# ── Templates cloned by the controller ── %>
  <template data-segment-builder-target="rowTemplate">
    <%= render_row({ "field" => "", "operator" => "", "value" => "" }) %>
  </template>
  <template data-segment-builder-target="groupTemplate">
    <%= render_group({ "type" => "group", "match" => "all", "conditions" => [] }, root: false) %>
  </template>
</div>
```

- [ ] **Step 5: Add the `render_group` / `render_row` helper methods** to the component class (so the ERB stays declarative and recursion works). Add inside `class SegmentBuilderComponent`, above `private`:

```ruby
    # Renders a group card. root groups omit the remove control & accent frame.
    def render_group(group, root:)
      match = group["match"].to_s == "any" ? "any" : "all"
      content_tag(:div,
        data: { "sb-group": "", "segment-builder-target": (root ? "groupRoot" : nil) }.compact,
        class: group_classes(root)) do
        safe_join([
          group_header(match, root),
          content_tag(:div, data: { "sb-rows": "" }, class: "space-y-2") do
            safe_join(Array(group["conditions"]).map { |m| group?(m) ? render_group(m, root: false) : render_row(m) })
          end,
          group_footer
        ])
      end
    end

    def render_row(cond)
      field_id = cond["field"].to_s
      operator = cond["operator"].to_s
      value    = cond["value"].to_s
      content_tag(:div, data: { "sb-row": "" },
        class: "flex flex-wrap items-center gap-2 p-3 bg-surface-subtle rounded-lg border border-border-subtle") do
        safe_join([
          field_select(field_id),
          operator_select(field_id, operator),
          value_input(value),
          remove_row_button
        ])
      end
    end

    private

    def group_classes(root)
      root ? "space-y-2" : "rounded-lg border-l-4 border-accent/60 bg-surface-subtle/60 pl-3 pr-3 py-3 space-y-2"
    end

    def group_header(match, root)
      content_tag(:div, class: "flex items-center justify-between gap-2") do
        safe_join([
          match_toggle(match),
          (root ? "".html_safe : remove_group_button)
        ])
      end
    end

    # AND/OR pill toggle for this group's match mode.
    def match_toggle(match)
      content_tag(:div, class: "inline-flex gap-0.5 p-0.5 bg-surface rounded-md border border-border-subtle",
                  data: { "sb-match": match }) do
        safe_join(%w[all any].map do |mode|
          active = mode == match
          label  = mode == "all" ? "AND" : "OR"
          content_tag(:button, label, type: "button",
            data: { "sb-match-value": mode, action: "segment-builder#setMatch" },
            class: "px-3 py-0.5 text-xs font-bold rounded transition-colors #{active ? "bg-accent text-white" : "text-text-secondary hover:text-text-primary"}")
        end)
      end
    end

    def group_footer
      content_tag(:div, class: "flex gap-2") do
        safe_join([
          content_tag(:button, "+ Add condition", type: "button",
            class: "btn btn-secondary text-xs", data: { action: "segment-builder#addRow" }),
          content_tag(:button, "+ Add group", type: "button",
            class: "btn btn-secondary text-xs", data: { action: "segment-builder#addGroup" })
        ])
      end
    end

    def field_select(field_id)
      opts = fields.map do |f|
        content_tag(:option, f[:label], value: f[:field], selected: (f[:field] == field_id))
      end
      content_tag(:select, safe_join(opts),
        class: "input-field min-w-0 flex-1 basis-40 text-sm",
        data: { "sb-field": "", action: "change->segment-builder#fieldChanged change->segment-builder#serialize" },
        "aria-label": "Field")
    end

    def operator_select(field_id, operator)
      opts = operators_for(field_id).map do |op|
        content_tag(:option, operator_label(op), value: op, selected: (op == operator))
      end
      content_tag(:select, safe_join(opts),
        class: "input-field min-w-0 flex-1 basis-36 text-sm",
        data: { "sb-operator": "", action: "change->segment-builder#serialize" },
        "aria-label": "Operator")
    end

    def value_input(value)
      tag.input(type: "text", value: value, placeholder: "Value",
        class: "input-field min-w-0 flex-1 basis-40 text-sm",
        data: { "sb-value": "", action: "input->segment-builder#serialize" },
        "aria-label": "Value")
    end

    def remove_row_button
      content_tag(:button, "Remove", type: "button",
        class: "btn btn-secondary text-xs shrink-0",
        data: { action: "segment-builder#removeRow" }, "aria-label": "Remove condition")
    end

    def remove_group_button
      content_tag(:button, "Remove group", type: "button",
        class: "btn btn-secondary text-xs shrink-0",
        data: { action: "segment-builder#removeGroup" }, "aria-label": "Remove group")
    end
```

Note: the existing `private` keyword that precedes `normalize` should now be the single `private` — remove the earlier standalone `private` from Step 3 so there is exactly one `private` section starting at `group_classes`, with `normalize`/`normalize_member` also under it. (Place `normalize`/`normalize_member` after the helper privates.)

- [ ] **Step 6: Run** `bundle exec rspec spec/components/email_campaigns/segment_builder_component_spec.rb` — expect PASS. Also confirm the legacy "edit form" examples (first_name selected, equals selected, value Ada, hidden output JSON) still pass via normalization.

- [ ] **Step 7: Commit**

```bash
git add app/components/email_campaigns/segment_builder_component.rb app/components/email_campaigns/segment_builder_component.html.erb spec/components/email_campaigns/segment_builder_component_spec.rb
git commit -m "feat(email_campaigns): grouped segment builder UI; remove Advanced raw JSON"
```

---

## Task 3: segment-builder Stimulus controller — tree DOM ↔ JSON, nesting

**Files:**
- Modify: `app/javascript/controllers/segment_builder_controller.js`

(No JS unit harness in this repo — per repo memory JS is covered by request/system specs. Verify by reading + the request spec in Task 4. Keep logic small and DOM-walk based.)

- [ ] **Step 1: Replace the controller** with a tree serializer:

```javascript
import { Controller } from "@hotwired/stimulus"

// segment-builder — grouped (nested AND/OR) condition builder for email list
// segment rules. Walks the DOM tree of [data-sb-group] / [data-sb-row] nodes
// and serializes the recursive group JSON into the hidden output input.
//
// Group JSON: { type:"group", match:"all"|"any", conditions:[ leaf | group ] }
// Leaf JSON:  { field, operator, value }
export default class extends Controller {
  static targets = ["output", "groupRoot", "rowTemplate", "groupTemplate"]
  static values  = { fields: Object }

  connect() {
    // Populate operator selects for every pre-rendered row from the catalog,
    // preserving the server-selected operator.
    this._allRows().forEach((row) => this._populateOperators(row, this._operatorOf(row)))
    this.serialize()
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  addRow(event) {
    const group = this._enclosingGroup(event.target)
    const clone = this.rowTemplateTarget.content.cloneNode(true)
    const rows  = group.querySelector("[data-sb-rows]")
    rows.appendChild(clone)
    const row = rows.lastElementChild
    this._populateOperators(row)
    this.serialize()
  }

  addGroup(event) {
    const group = this._enclosingGroup(event.target)
    const clone = this.groupTemplateTarget.content.cloneNode(true)
    const rows  = group.querySelector("[data-sb-rows]")
    rows.appendChild(clone)
    this.serialize()
  }

  removeRow(event) {
    const row = event.target.closest("[data-sb-row]")
    if (row) row.remove()
    this.serialize()
  }

  removeGroup(event) {
    const group = event.target.closest("[data-sb-group]")
    // Never remove the root group.
    if (group && group !== this.groupRootTarget) group.remove()
    this.serialize()
  }

  setMatch(event) {
    const btn    = event.currentTarget
    const toggle = btn.closest("[data-sb-match]")
    toggle.setAttribute("data-sb-match", btn.getAttribute("data-sb-match-value"))
    // Restyle the two pills.
    toggle.querySelectorAll("[data-sb-match-value]").forEach((b) => {
      const active = b === btn
      b.className = "px-3 py-0.5 text-xs font-bold rounded transition-colors " +
        (active ? "bg-accent text-white" : "text-text-secondary hover:text-text-primary")
    })
    this.serialize()
  }

  fieldChanged(event) {
    const row = event.target.closest("[data-sb-row]")
    if (row) this._populateOperators(row)
    this.serialize()
  }

  // ── Serialization ────────────────────────────────────────────────────────

  serialize() {
    if (!this.hasGroupRootTarget) return
    const tree = this._readGroup(this.groupRootTarget)
    this.outputTarget.value = JSON.stringify(tree)
  }

  _readGroup(groupEl) {
    const match = this._matchOf(groupEl)
    const rows  = groupEl.querySelector(":scope > [data-sb-rows]")
    const conditions = []
    if (rows) {
      Array.from(rows.children).forEach((child) => {
        if (child.matches("[data-sb-group]")) {
          conditions.push(this._readGroup(child))
        } else if (child.matches("[data-sb-row]")) {
          const leaf = this._readRow(child)
          if (leaf.field && leaf.operator) conditions.push(leaf)
        }
      })
    }
    return { type: "group", match, conditions }
  }

  _readRow(row) {
    const f = row.querySelector("[data-sb-field]")
    const o = row.querySelector("[data-sb-operator]")
    const v = row.querySelector("[data-sb-value]")
    return { field: f ? f.value : "", operator: o ? o.value : "", value: v ? v.value : "" }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  _enclosingGroup(el) {
    return el.closest("[data-sb-group]") || this.groupRootTarget
  }

  _matchOf(groupEl) {
    const toggle = groupEl.querySelector(":scope > div [data-sb-match]")
    const mode = toggle ? toggle.getAttribute("data-sb-match") : "all"
    return mode === "any" ? "any" : "all"
  }

  _operatorOf(row) {
    const o = row.querySelector("[data-sb-operator]")
    return o ? o.value : null
  }

  _populateOperators(row, selectedOperator = null) {
    const fieldEl = row.querySelector("[data-sb-field]")
    const opEl    = row.querySelector("[data-sb-operator]")
    if (!fieldEl || !opEl) return
    const meta = this.fieldsValue[fieldEl.value]
    const operators = meta ? meta.operators : []
    const current = selectedOperator || opEl.value
    opEl.innerHTML = ""
    operators.forEach((op) => {
      const opt = document.createElement("option")
      opt.value = op
      opt.textContent = op.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase())
      if (op === current) opt.selected = true
      opEl.appendChild(opt)
    })
  }

  _allRows() {
    if (!this.hasGroupRootTarget) return []
    return Array.from(this.groupRootTarget.querySelectorAll("[data-sb-row]"))
  }
}
```

- [ ] **Step 2: Sanity-check** the `_matchOf` selector against the rendered header markup (the match toggle is `[data-sb-match]` inside the group header div). If the header structure differs, adjust the `:scope > div [data-sb-match]` selector to `:scope [data-sb-match]` scoped to the nearest group — but a nested group's own toggle must not be read by its parent. Since `_readGroup` recurses per child group and reads each group's own header, scope the match lookup to the header that is a *direct* descendant: use `groupEl.querySelector(':scope > div [data-sb-match]')` and ensure the group header is the first child `div` (it is, per the component's `group_header`). Verify in Task 4's system check.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/segment_builder_controller.js
git commit -m "feat(email_campaigns): grouped segment-builder Stimulus tree serializer"
```

---

## Task 4: Lists controller guard + request/round-trip spec (B7)

**Files:**
- Modify: `app/controllers/admin/modules/email_campaigns/lists_controller.rb`
- Test: `spec/requests/admin/modules/email_campaigns/lists_spec.rb`

- [ ] **Step 1: Add a request spec** asserting a nested group round-trips into `segment_rules`. Append within the existing describe (use the existing auth/login helpers already in the file — match their pattern; below assumes `sign_in_admin(customer)` style already present, otherwise mirror the file's setup):

```ruby
  it "persists a nested group from segment_rules_json" do
    nested = {
      "type" => "group", "match" => "all",
      "conditions" => [
        { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
        { "type" => "group", "match" => "any", "conditions" => [
          { "field" => "roles.key", "operator" => "equals", "value" => "admin" }
        ] }
      ]
    }
    post lists_create_path, params: { email_list: {
      name: "Nested", status: "active", segment_rules_json: nested.to_json
    } }
    list = EmailCampaigns::List.order(:created_at).last
    expect(list.segment_rules["conditions"].size).to eq(2)
    expect(list.segment_rules["conditions"][1]["match"]).to eq("any")
  end
```

(Use the exact path/login helpers already used by sibling examples in this spec file — read the top of the file and reuse them.)

- [ ] **Step 2: Run** `bundle exec rspec spec/requests/admin/modules/email_campaigns/lists_spec.rb` — expect the new example to PASS already (the controller stores parsed JSON verbatim). If it fails on path helpers, fix the spec to match existing ones.

- [ ] **Step 3: Harden `list_params`** so malformed JSON surfaces instead of silently wiping. Replace the `list_params` method:

```ruby
      def list_params
        permitted = params.require(:email_list).permit(:name, :description, :status)

        raw = params[:email_list][:segment_rules_json]
        if raw.is_a?(String) && raw.present?
          begin
            permitted[:segment_rules] = JSON.parse(raw)
          rescue JSON::ParserError
            @segment_rules_error = true
          end
        end

        permitted
      end
```

And guard create/update to reject on parse error. In `create`, before `@list.save`:

```ruby
      def create
        @list = ::EmailCampaigns::List.new(list_params.merge(customer: current_customer))
        if @segment_rules_error
          @list.errors.add(:base, "Segment rules were malformed — please rebuild the audience.")
          return render :new, status: :unprocessable_entity
        end
        if @list.save
          redirect_to lists_path, notice: "List created"
        else
          render :new, status: :unprocessable_entity
        end
      end
```

Apply the same `@segment_rules_error` guard at the top of `update` (add the error to `@list` and `render :edit, status: :unprocessable_entity`).

- [ ] **Step 4: Add a spec** for the malformed-JSON guard:

```ruby
  it "re-renders with an error when segment_rules_json is malformed" do
    post lists_create_path, params: { email_list: {
      name: "Bad", status: "active", segment_rules_json: "{not json"
    } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(EmailCampaigns::List.where(name: "Bad")).to be_empty
  end
```

- [ ] **Step 5: Run** `bundle exec rspec spec/requests/admin/modules/email_campaigns/lists_spec.rb` — expect PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/modules/email_campaigns/lists_controller.rb spec/requests/admin/modules/email_campaigns/lists_spec.rb
git commit -m "fix(email_campaigns): surface malformed segment JSON instead of wiping rules"
```

---

## Task 5: Campaign send dedupe — no double-send on resume (B1)

**Files:**
- Modify: `app/jobs/email_campaigns/send_campaign_job.rb`
- Modify: `app/services/email/gateway.rb` (`queue_for_campaign` accepts an idempotency key)
- Test: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`

- [ ] **Step 1: Add failing tests** to `send_campaign_job_spec.rb`:

```ruby
    it "does not re-send to users already emailed when run twice (resume safe)" do
      described_class.new.perform(campaign.id)
      first_count = Emails::Message.where(message_type: "campaign").count

      campaign.update!(status: "sending") # simulate resume
      described_class.new.perform(campaign.id)

      expect(Emails::Message.where(message_type: "campaign").count).to eq(first_count)
    end
```

- [ ] **Step 2: Run** `bundle exec rspec spec/jobs/email_campaigns/send_campaign_job_spec.rb` — expect the new example to FAIL (currently doubles).

- [ ] **Step 3: Add a per-(campaign,user) idempotency key + skip-already-sent** in `send_campaign_job.rb`. Replace the file body:

```ruby
# frozen_string_literal: true

module EmailCampaigns
  class SendCampaignJob < ApplicationJob
    queue_as :default

    def perform(campaign_id)
      campaign = EmailCampaigns::Campaign.find(campaign_id)
      return unless campaign.status == "sending"

      blob_ids = Emails::CompileTemplate.blob_ids_for(campaign.email_template)
      already  = already_sent_user_ids(campaign)

      campaign.email_list.audience.campaign_deliverable.find_each do |user|
        campaign.reload
        break unless campaign.status == "sending"
        next if already.include?(user.id)

        send_to_user(campaign, user, blob_ids)
      end

      campaign.reload
      campaign.complete! if campaign.status == "sending"
    end

    private

    # User ids that already have a campaign message for this campaign — the
    # Emails::Message rows are the per-recipient ledger, so a resumed run skips
    # everyone already emailed (no duplicate sends).
    def already_sent_user_ids(campaign)
      Emails::Message
        .where(customer_id: campaign.customer_id, message_type: "campaign")
        .where("json_extract(metadata, '$.campaign_id') = ?", campaign.id)
        .pluck(Arel.sql("json_extract(metadata, '$.user_id')"))
        .compact
        .map(&:to_i)
        .to_set
    end

    def send_to_user(campaign, user, blob_ids)
      Email::Gateway.queue_for_campaign(
        campaign:            campaign,
        user:                user,
        attachment_blob_ids: blob_ids,
        idempotency_key:     "campaign-#{campaign.id}-user-#{user.id}"
      )
      campaign.increment_stat!(:sent_count)
    rescue => e
      campaign.increment_stat!(:failed_count)
      Rails.logger.error("Campaign #{campaign.id} send to #{user.email} failed: #{e.message}")
    end
  end
end
```

(Repo memory confirms JSON columns are queried with `json_extract` — this matches the existing pattern.)

- [ ] **Step 4: Update `queue_for_campaign`** in `gateway.rb` to accept and persist `idempotency_key`, returning the existing message if present. Replace the method:

```ruby
      def queue_for_campaign(campaign:, user:, attachment_blob_ids: nil, idempotency_key: nil)
        if idempotency_key.present?
          existing = Emails::Message.find_by(customer_id: campaign.customer.id, idempotency_key: idempotency_key)
          return existing if existing
        end

        template = campaign.email_template
        vars     = Email::VariableContext.for(user: user)
        rendered = TemplateRenderer.render(template: template, vars: vars)
        blob_ids = attachment_blob_ids || Emails::CompileTemplate.blob_ids_for(template)

        credential = CredentialResolver.call(mode: CredentialResolver.default_mode)

        message = Emails::Message.create!(
          customer:        campaign.customer,
          email_template:  template,
          to:              user.email,
          from:            credential.username,
          subject:         rendered[:subject],
          body_html:       rendered[:body_html],
          body_text:       rendered[:body_text],
          status:          "queued",
          message_type:    "campaign",
          idempotency_key: idempotency_key,
          metadata:        {
            campaign_id:         campaign.id,
            user_id:             user.id,
            attachment_blob_ids: blob_ids
          }
        )

        DeliveryJob.perform_later(message.id)
        message
      end
```

- [ ] **Step 5: Run** `bundle exec rspec spec/jobs/email_campaigns/send_campaign_job_spec.rb` — expect PASS (including the existing examples; the per-user idempotency key is unique so first-run counts are unchanged).

- [ ] **Step 6: Commit**

```bash
git add app/jobs/email_campaigns/send_campaign_job.rb app/services/email/gateway.rb spec/jobs/email_campaigns/send_campaign_job_spec.rb
git commit -m "fix(email_campaigns): dedupe campaign sends so resume never double-sends"
```

---

## Task 6: Scheduler roll-forward (B5)

**Files:**
- Modify: `app/jobs/email_campaigns/scheduler_job.rb`
- Test: `spec/jobs/email_campaigns/scheduler_job_spec.rb`

- [ ] **Step 1: Add a failing test** to `scheduler_job_spec.rb`:

```ruby
  it "rolls a recurring occurrence forward past now when the base time is stale" do
    campaign = create(:email_campaign, :recurring, customer: create(:customer),
                      status: "scheduled", scheduled_at: 5.days.ago)
    described_class.new.perform
    nxt = EmailCampaigns::Campaign.where(status: "scheduled").order(:created_at).last
    expect(nxt.scheduled_at).to be > Time.current
  end
```

- [ ] **Step 2: Run** `bundle exec rspec spec/jobs/email_campaigns/scheduler_job_spec.rb` — expect the new example to FAIL (next time would be 4 days ago).

- [ ] **Step 3: Roll forward** in `scheduler_job.rb`. Replace `compute_next_occurrence`:

```ruby
    def compute_next_occurrence(campaign)
      rule = parse_rrule(campaign.recurrence_rule)
      return nil unless rule

      interval = rule["INTERVAL"]&.to_i
      interval = 1 if interval.nil? || interval <= 0
      step = case rule["FREQ"]
             when "DAILY"   then interval.days
             when "WEEKLY"  then interval.weeks
             when "MONTHLY" then interval.months
             when "HOURLY"  then interval.hours
             end
      return nil unless step

      # Advance from the scheduled base until strictly in the future, so a
      # delayed run never emits an already-past occurrence (catch-up storm).
      next_at = campaign.scheduled_at + step
      next_at += step while next_at <= Time.current
      next_at
    end
```

- [ ] **Step 4: Run** `bundle exec rspec spec/jobs/email_campaigns/scheduler_job_spec.rb` — expect PASS.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/email_campaigns/scheduler_job.rb spec/jobs/email_campaigns/scheduler_job_spec.rb
git commit -m "fix(email_campaigns): roll recurring occurrences past now (no catch-up storm)"
```

---

## Task 7: Campaign destroy guard (B6)

**Files:**
- Modify: `app/controllers/admin/modules/email_campaigns/campaigns_controller.rb`
- Test: `spec/requests/admin/modules/email_campaigns/campaigns_spec.rb`

- [ ] **Step 1: Add failing tests** to `campaigns_spec.rb` (reuse existing login/path helpers in that file):

```ruby
  it "refuses to delete a sending campaign" do
    campaign = create(:email_campaign, :sending, customer: customer,
                      email_template: create(:email_template, customer: customer),
                      email_list: create(:email_list, customer: customer))
    delete campaign_path(campaign)
    expect(EmailCampaigns::Campaign.exists?(campaign.id)).to be true
  end

  it "allows deleting a draft campaign" do
    campaign = create(:email_campaign, customer: customer,
                      email_template: create(:email_template, customer: customer),
                      email_list: create(:email_list, customer: customer))
    delete campaign_path(campaign)
    expect(EmailCampaigns::Campaign.exists?(campaign.id)).to be false
  end
```

(Match the exact `campaign_path`/login helper style already used in the file.)

- [ ] **Step 2: Run** `bundle exec rspec spec/requests/admin/modules/email_campaigns/campaigns_spec.rb` — expect the "refuses" example to FAIL.

- [ ] **Step 3: Guard destroy** in `campaigns_controller.rb`. Replace `destroy`:

```ruby
      DESTROYABLE_STATUSES = %w[draft sent cancelled].freeze

      def destroy
        unless DESTROYABLE_STATUSES.include?(@campaign.status)
          return redirect_to "/#{current_customer.id}/admin/modules/email_campaigns/campaigns/#{@campaign.id}",
                             alert: "Cannot delete a campaign while it is #{@campaign.status}. Pause or cancel it first."
        end
        @campaign.destroy
        redirect_to "/#{current_customer.id}/admin/modules/email_campaigns/campaigns", notice: "Campaign deleted"
      end
```

(Place the `DESTROYABLE_STATUSES` constant near the top of the controller class instead of inside the method if the linter prefers; either is fine.)

- [ ] **Step 4: Run** `bundle exec rspec spec/requests/admin/modules/email_campaigns/campaigns_spec.rb` — expect PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/modules/email_campaigns/campaigns_controller.rb spec/requests/admin/modules/email_campaigns/campaigns_spec.rb
git commit -m "fix(email_campaigns): guard against deleting in-flight campaigns"
```

---

## Task 8: Template test-send renders inline images (B4)

**Files:**
- Modify: `app/services/email/gateway.rb` (`send_raw` accepts `attachment_blob_ids`)
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` (`test_send` passes blob ids)
- Test: `spec/requests/admin/modules/emails/templates_spec.rb` (or create if absent)

- [ ] **Step 1: Check** for an existing templates request spec: `ls spec/requests/admin/modules/emails/`. If `templates_spec.rb` exists, append; else create it with the standard request-spec scaffold mirroring `email_campaigns` request specs (same login helper). Add:

```ruby
  it "test_send persists inline attachment blob ids into message metadata" do
    template = create(:email_template, customer: customer, editor_type: "code",
                      body_html: '<img src="cid:blob-1">')
    allow(Emails::CompileTemplate).to receive(:blob_ids_for).and_return([42])

    post test_send_template_path(template), params: { to: "me@example.com" }

    msg = Emails::Message.order(:created_at).last
    expect(msg.metadata["attachment_blob_ids"]).to eq([42])
  end
```

(Use the exact path/login helpers present in sibling specs.)

- [ ] **Step 2: Run** the spec — expect FAIL (`send_raw` ignores blob ids; metadata empty).

- [ ] **Step 3: Add `attachment_blob_ids:` to `send_raw`** in `gateway.rb`. Replace the method signature + create call:

```ruby
      def send_raw(customer:, to:, subject:, body_html:, body_text: nil, cc: nil, bcc: nil, from: nil, reply_to: nil, idempotency_key: nil, mode: nil, attachment_blob_ids: nil)
        if idempotency_key.present?
          existing = Emails::Message.find_by(customer_id: customer.id, idempotency_key: idempotency_key)
          return existing if existing
        end

        credential   = CredentialResolver.call(mode: mode || CredentialResolver.default_mode)
        from_address = from || credential.username

        message = Emails::Message.create!(
          customer:        customer,
          to:              to,
          from:            from_address,
          cc:              cc,
          bcc:             bcc,
          reply_to:        reply_to,
          subject:         subject,
          body_html:       body_html,
          body_text:       body_text || TemplateRenderer.strip_html(body_html),
          status:          "queued",
          message_type:    "transactional",
          idempotency_key: idempotency_key,
          metadata:        { attachment_blob_ids: Array(attachment_blob_ids) }
        )

        DeliveryJob.perform_later(message.id, mode: mode)
        message
      end
```

- [ ] **Step 4: Pass blob ids from `test_send`** in `templates_controller.rb`. Replace the `Email::Gateway.send_raw(...)` call:

```ruby
        Email::Gateway.send_raw(
          customer:            current_customer,
          to:                  to,
          subject:             rendered[:subject],
          body_html:           rendered[:body_html],
          body_text:           rendered[:body_text],
          attachment_blob_ids: Emails::CompileTemplate.blob_ids_for(@template)
        )
```

- [ ] **Step 5: Run** the templates request spec — expect PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/email/gateway.rb app/controllers/admin/modules/emails/templates_controller.rb spec/requests/admin/modules/emails/templates_spec.rb
git commit -m "fix(emails): test-send attaches inline images so previews render"
```

---

## Task 9: Full regression + asset rebuild + smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the email-related suite**

```bash
bundle exec rspec \
  spec/services/email_campaigns spec/components/email_campaigns \
  spec/models/email_campaigns spec/jobs/email_campaigns \
  spec/requests/admin/modules/email_campaigns spec/requests/admin/modules/emails \
  spec/services/email spec/services/emails
```

Expected: all PASS. Fix any regression before proceeding.

- [ ] **Step 2: Rebuild assets + smoke the new-list page** (JS controller change requires asset rebuild). Per AGENTS.md:

```bash
rm -f public/assets/.manifest.json
yarn build 2>/dev/null || bin/rails assets:precompile 2>/dev/null || true
```

Then start the dev server with `SKIP_AUTH=1` and GET `/81721200/admin/modules/email_campaigns/lists/new`; confirm 200 and that the grouped builder + "Add group" render and no "Advanced" text appears.

- [ ] **Step 3: Final commit** (if any asset artifacts changed)

```bash
git add -A && git commit -m "chore(email): rebuild assets for grouped segment builder" || echo "nothing to commit"
```

---

## Self-Review notes

- **Spec coverage:** B1→T5, B2/B3→T1, B4→T8, B5→T6, B6→T7, B7→T4, Part 2 (remove Advanced)→T2, Part 3 (grouped builder)→T1+T2+T3. All covered.
- **Type consistency:** group JSON shape `{type,match,conditions}` is identical across AudienceQuery (T1), component (T2), Stimulus (T3), and request round-trip (T4). Data attributes `data-sb-group/-rows/-row/-field/-operator/-value/-match` are consistent between T2 (render) and T3 (read).
- **Normalization** in both AudienceQuery and the component guarantees legacy flat lists keep working — no migration, existing specs stay green.
- **Risk note (conservative):** the `_matchOf` selector in T3 depends on the group-header DOM; T3 Step 2 + T9 smoke verify it in a real browser before claiming done.
