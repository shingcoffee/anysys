# frozen_string_literal: true

module Emails
  module Audience
    # Renders a grouped (nested AND/OR) condition builder for an email list's
    # segment rules, modeled EXACTLY on the flowchart Decision element's condition
    # builder (app/javascript/.../branch_manager/condition_builder.js).
    #
    # segment_rules canonical shape (recursive, per-join):
    #   { "type" => "group",
    #     "joins" => ["AND"|"OR", ...],   # length == conditions.length - 1
    #     "conditions" => [ leaf | group, ... ] }
    #   leaf: { "field" =>, "operator" =>, "value" => }
    #
    # Between every two adjacent members sits an INDEPENDENT AND/OR pill toggle
    # (just like the flowchart): clicking it flips only that one join. Members are
    # combined left-associatively by SegmentQuery.
    #
    # The component pre-renders the tree server-side (so the form is usable before
    # JS hydrates); the `segment-builder` Stimulus controller keeps the hidden JSON
    # output input in sync with the visible tree.
    #
    # @param list    [Emails::Audience::List]        the list whose segment_rules to build
    # @param catalog [Emails::SendActivities::FieldCatalog] source of queryable field metadata
    # @param preview [Boolean] when true, root footer includes Preview after Add group
    class SegmentBuilderComponent < ViewComponent::Base
      # @param output_data [Hash] extra data-* attributes merged onto the hidden
      #   JSON output input, so a host form can hang its own Stimulus target on
      #   the field without reaching into this component's markup.
      def initialize(list:, catalog: Emails::SendActivities::FieldCatalog.new,
                     param_name: "email_list[segment_rules_json]", preview: false,
                     output_data: {})
        @list        = list
        @catalog     = catalog
        @param_name  = param_name
        @preview     = preview
        @output_data = output_data || {}
      end

      attr_reader :list, :catalog, :param_name, :output_data

      def preview? = @preview

      # All queryable fields for the field <select>.
      def fields
        catalog.fields
      end

      # Normalized root group from list.segment_rules (handles the legacy shape).
      def root_group
        @root_group ||= normalize(list.segment_rules)
      end

      # The initial JSON for the hidden output field (compact, for the controller).
      def output_json
        JSON.generate(root_group)
      end

      # Operators for a given field id, derived from the catalog.
      def operators_for(field_id)
        entry = fields.find { |f| f[:field] == field_id }
        entry ? entry[:operators] : Emails::SendActivities::FieldCatalog::OPERATORS_BY_TYPE[:string]
      end

      # Full catalog serialized as JSON for the Stimulus `fields` value.
      # Shape: { "<field_id>": { label: "...", operators: [...] }, ... }
      def fields_value_json
        map = fields.each_with_object({}) do |f, h|
          h[f[:field]] = { label: f[:label], operators: f[:operators] }
        end
        JSON.generate(map)
      end

      # Human-readable label for an operator key.
      def operator_label(op)
        I18n.t("comp_misc.segment_builder.operators.#{op}", default: op.to_s)
      end

      def operator_labels_json
        keys = Emails::SendActivities::FieldCatalog::OPERATORS_BY_TYPE.values.flatten.uniq
        JSON.generate(keys.index_with { |op| operator_label(op) })
      end

      # True when the member hash is a nested group.
      def group?(member)
        member.is_a?(Hash) && (member["type"].to_s == "group" || member.key?("conditions"))
      end

      # ── Recursive rendering ───────────────────────────────────────────────────

      # Renders a group card. The root group omits the remove control and frame.
      # Members are interleaved with per-join AND/OR toggles, exactly like the
      # flowchart's _buildGroupHTML.
      def render_group(group, root:)
        members = Array(group["conditions"])
        joins   = Array(group["joins"])

        rows = [].tap do |acc|
          members.each_with_index do |m, idx|
            acc << join_toggle(joins[idx - 1]) if idx.positive?
            acc << (group?(m) ? render_group(m, root: false) : render_row(m))
          end
        end

        content_tag(:div,
          data: { "sb-group": "", "segment-builder-target": (root ? "groupRoot" : nil) }.compact,
          class: group_classes(root)) do
          safe_join([
            (root ? "".html_safe : group_header),
            content_tag(:div, data: { "sb-rows": "" }, class: "space-y-4") { safe_join(rows) },
            group_footer(root: root)
          ])
        end
      end

      def render_row(cond)
        field_id = cond["field"].to_s
        operator = cond["operator"].to_s
        value    = cond["value"].to_s
        content_tag(:div, data: { "sb-row": "" },
          class: "group relative rounded-xl border border-border-subtle bg-white dark:bg-zinc-900 p-4 sm:p-5 shadow-sm") do
          content_tag(:div, class: "grid grid-cols-1 gap-4 sm:grid-cols-12 sm:gap-4 sm:items-end") do
            safe_join([
              labeled_control(I18n.t("comp_misc.segment_builder.field_aria"), "sm:col-span-4") { field_select(field_id) },
              labeled_control(I18n.t("comp_misc.segment_builder.operator_aria"), "sm:col-span-3") { operator_select(field_id, operator) },
              labeled_control(I18n.t("comp_misc.segment_builder.value"), "sm:col-span-4") { value_input(value) },
              content_tag(:div, class: "sm:col-span-1 flex sm:justify-end sm:pb-0.5") { remove_row_button }
            ])
          end
        end
      end

      private

      def group_classes(root)
        if root
          # Outermost audience card wraps conditions, nested groups, and action
          # buttons. When [data-sb-rows] is empty, give the card a min-height and
          # vertically center the footer buttons; once rows exist, drop min-height.
          # sb-rows must remain a direct child of sb-group for segment-builder.
          "rounded-xl border border-border-subtle bg-surface-subtle/40 p-4 sm:p-5 " \
            "flex flex-col gap-4 min-h-28 " \
            "has-[[data-sb-rows]:not(:empty)]:min-h-0 " \
            "[&:has([data-sb-rows]:empty)_[data-sb-footer]]:flex-1 " \
            "[&:has([data-sb-rows]:empty)_[data-sb-footer]]:items-center"
        else
          "group relative rounded-xl border border-border-subtle bg-canvas-elevated/80 p-4 sm:p-5 space-y-4"
        end
      end

      # A single independent AND/OR pill toggle that sits BETWEEN two members.
      # Carries its own state in data-sb-join; clicking flips only this toggle.
      # The button text is translated. data-sb-join stays the AND/OR token
      # that serialization and the query compiler read.
      def join_toggle(join)
        op = join.to_s.upcase == "OR" ? "OR" : "AND"
        label = I18n.t(op == "OR" ? "comp_misc.segment_builder.or" : "comp_misc.segment_builder.and")
        content_tag(:div, class: "flex items-center justify-center py-2", data: { "sb-join-wrap": "" }) do
          content_tag(:button, label, type: "button",
            data: { "sb-join": op, action: "segment-builder#toggleJoin" },
            class: "min-w-[4.5rem] px-4 py-1.5 text-xs font-semibold tracking-wide rounded-full transition-colors #{join_pill_classes(op)}")
        end
      end

      # Match the flowchart's decision scheme: AND amber, OR purple.
      def join_pill_classes(op)
        op == "OR" ? "bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-200" : "bg-amber-100 text-amber-900 dark:bg-amber-900/40 dark:text-amber-200"
      end

      def group_header
        content_tag(:div, class: "flex items-center justify-between gap-3 pb-1", data: { "sb-header": "" }) do
          safe_join([
            content_tag(:span, I18n.t("comp_misc.segment_builder.group"), class: "text-xs font-semibold uppercase tracking-wider text-text-muted"),
            remove_group_button
          ])
        end
      end

      def group_footer(root:)
        buttons = [
          content_tag(:button, I18n.t("comp_misc.segment_builder.add_condition"), type: "button",
            class: "btn btn-secondary text-sm", data: { action: "segment-builder#addRow" }),
          content_tag(:button, I18n.t("comp_misc.segment_builder.add_group"), type: "button",
            class: "btn btn-secondary text-sm", data: { action: "segment-builder#addGroup" })
        ]
        if root && preview?
          buttons << content_tag(:button, I18n.t("admin_modules.emails.lists.preview.button"), type: "button",
            class: "btn btn-secondary text-sm",
            data: {
              action: "email-list-form#preview",
              "email-list-form-target": "previewButton"
            })
        end

        content_tag(:div,
          data: { "sb-footer": "" },
          class: "flex flex-wrap gap-3") { safe_join(buttons) }
      end

      def labeled_control(label, wrapper_class)
        content_tag(:div, class: "#{wrapper_class} space-y-1.5") do
          safe_join([
            content_tag(:span, label, class: "block text-caption font-medium text-text-muted"),
            yield
          ])
        end
      end

      def field_select(field_id)
        opts = fields.map do |f|
          content_tag(:option, f[:label], value: f[:field], selected: (f[:field] == field_id))
        end
        content_tag(:select, safe_join(opts),
          class: "input-field w-full text-sm",
          data: { "sb-field": "", action: "change->segment-builder#fieldChanged change->segment-builder#serialize" },
          "aria-label": I18n.t("comp_misc.segment_builder.field_aria"))
      end

      def operator_select(field_id, operator)
        opts = operators_for(field_id).map do |op|
          content_tag(:option, operator_label(op), value: op, selected: (op == operator))
        end
        content_tag(:select, safe_join(opts),
          class: "input-field w-full text-sm",
          data: { "sb-operator": "", action: "change->segment-builder#serialize" },
          "aria-label": I18n.t("comp_misc.segment_builder.operator_aria"))
      end

      def value_input(value)
        tag.input(type: "text", value: value, placeholder: I18n.t("comp_misc.segment_builder.value"),
          class: "input-field w-full text-sm",
          data: { "sb-value": "", action: "input->segment-builder#serialize" },
          "aria-label": I18n.t("comp_misc.segment_builder.value"))
      end

      # Professional remove control: outlined minus-in-circle (list-remove
      # affordance), using design-system action-icon styles. Hidden until the
      # parent row/group is hovered or focused; always visible on small screens.
      def remove_row_button
        content_tag(:button, type: "button",
          class: remove_icon_button_classes,
          data: { action: "segment-builder#removeRow" },
          "aria-label": I18n.t("comp_misc.segment_builder.remove_condition_aria")) do
          remove_icon
        end
      end

      def remove_group_button
        content_tag(:button, type: "button",
          class: remove_icon_button_classes,
          data: { action: "segment-builder#removeGroup" },
          "aria-label": I18n.t("comp_misc.segment_builder.remove_group")) do
          remove_icon
        end
      end

      def remove_icon_button_classes
        "action-icon action-icon-danger shrink-0 " \
          "opacity-100 pointer-events-auto transition-opacity " \
          "sm:opacity-0 sm:pointer-events-none " \
          "sm:group-hover:opacity-100 sm:group-hover:pointer-events-auto " \
          "sm:group-focus-within:opacity-100 sm:group-focus-within:pointer-events-auto " \
          "focus-visible:opacity-100 focus-visible:pointer-events-auto"
      end

      # Minus-in-circle: clearer hit target and more intentional than a bare dash.
      # Geometry mirrors the rest of the app's 24×24 stroke icons (round caps,
      # 1.75 stroke for slightly finer admin chrome).
      def remove_icon
        content_tag(:svg,
          class: "w-4 h-4", fill: "none", viewBox: "0 0 24 24",
          stroke: "currentColor", "stroke-width": "1.75", "aria-hidden": true) do
          safe_join([
            tag.circle(cx: "12", cy: "12", r: "9"),
            tag.path("stroke-linecap": "round", d: "M8.5 12h7")
          ])
        end
      end

      # ── Normalization ──────────────────────────────────────────────────────────

      # Canonical form: { type:"group", joins:[...], conditions:[...] }.
      # Legacy { match:"all"|"any" } fills every join with the same operator.
      def normalize(node)
        node = (node || {})
        node = node.deep_stringify_keys if node.respond_to?(:deep_stringify_keys)

        conditions = Array(node["conditions"]).map { |m| normalize_member(m) }
        joins      = Array(node["joins"]).map { |j| j.to_s.upcase == "OR" ? "OR" : "AND" }

        if joins.empty? && node.key?("match")
          op    = node["match"].to_s == "any" ? "OR" : "AND"
          joins = Array.new([conditions.length - 1, 0].max, op)
        end

        # Keep joins aligned to (conditions.length - 1).
        target = [conditions.length - 1, 0].max
        joins  = joins.first(target) + Array.new([target - joins.length, 0].max, "AND")

        { "type" => "group", "joins" => joins, "conditions" => conditions }
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
end
