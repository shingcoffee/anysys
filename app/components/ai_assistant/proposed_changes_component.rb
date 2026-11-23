# frozen_string_literal: true

module AiAssistant
  # The change list for an update the assistant has proposed but not saved.
  #
  # The server parks the proposal on the assistant message and emits raw
  # machine values only — hashes and arrays included, nothing pre-joined or
  # pre-formatted — so every word on screen is chosen here, at render time, in
  # the admin's locale.
  #
  # **Nothing is dropped for want of wording.** update_entity applies nothing
  # until the admin approves this plan, so the plan is what makes the gate
  # safe: a row this component declines to render is a real change the admin
  # approves blind. An unrecognised `field` or `config_key` therefore falls
  # back to a generic label, and only structural junk — a row that is not a
  # hash, a relabel entry missing a side — is discarded. An entry left with no
  # rows at all (the server's `unplannable` flag, or junk all the way down)
  # renders a "could not describe this" line rather than an empty card.
  #
  # `state` is what the footer offers. Apply is pinned to this message; a
  # newer parked proposal retires older panels.
  class ProposedChangesComponent < ApplicationComponent
    STATES = %i[pending applied declined superseded].freeze

    # Every `field` a row can carry, and the one key per field this component
    # words it with. Deliberately a literal list rather than a reference to
    # ChangePlan.identity_fields / .attribute_fields: the cross-layer guard in
    # spec/services/entity_definitions/assistant/plan_field_labels_spec.rb
    # exists to catch drift between the two, and it can only do that while
    # they are maintained independently. A field missing here still renders,
    # under `plan.field_other`.
    FIELDS = %w[
      icon color description referenced_template display_label name_slug extended_model
      name html_type type formula visibility validator_apply readonly storage
      validators options options_source config group_id owner editable lifecycle
    ].freeze

    # Settings inside an attribute's config blob that have wording of their own.
    # The first group is every key Normalizer keeps on an attribute config
    # (`INPUT_CONFIG_KEYS ∪ COMPUTED_CONFIG_KEYS`), which is what a row's
    # `config_key` is bounded by; the second is the keys found *inside* the
    # object values some of them hold — `filter` is `{slug, op, value}`, and a
    # choice option may carry `default`. Both are looked up in
    # `plan.config_fields`, and anything else words itself with
    # `plan.config_field_other`.
    CONFIG_FIELDS = %w[
      options options_source options_entity_name label_field
      source constant_id constant_name accept multiple
      target_entity_name function source_slug precision filter bridge_role
      slug op value default
    ].freeze

    # kind => the actions this component has specific wording for. A pairing
    # outside this table is still rendered, generically.
    ACTIONS = {
      "identity" => %w[modified],
      "attribute" => %w[added modified],
      "attribute_removed" => %w[removed],
      "group" => %w[added modified removed],
      "association" => %w[added modified removed],
      "default_properties" => %w[modified]
    }.freeze

    # Kinds whose wording names the thing that changed. A nameless one has no
    # sentence to fill, so it falls back to the generic label.
    NAMED = %w[attribute attribute_removed group association].freeze

    # How far into a value's own structure the wording goes before it stops
    # describing and starts saying "there is more in here". A filter is one
    # level deep; nothing in the schema is deeper.
    MAX_VALUE_DEPTH = 3

    # Characters of any one value kept on screen. A single option label or
    # formula is unbounded, and the panel sits in a chat bubble.
    MAX_VALUE_LENGTH = 120

    # Punctuation, not wording: the same character in both locales.
    ELLIPSIS = "…"

    Entry = Struct.new(:name, :rows, keyword_init: true)
    # `values` are standalone chips (an option list); `pairs` are before/after
    # chips. A scalar change is a single pair, so one render branch covers both
    # it and a list of relabelled options. A `note` row is a footnote about the
    # list rather than a change in it — what the server left out.
    Row = Struct.new(:label, :breaking, :values, :pairs, :note, keyword_init: true)

    attr_reader :state

    def initialize(proposal:, state: :pending, message_id: nil, discard_path: nil)
      @proposal = proposal.is_a?(Hash) ? proposal : {}
      @state = STATES.include?(state) ? state : :pending
      @message_id = message_id
      @discard_path = discard_path
    end

    # A flowchart proposal and an older proposal with no plan have nothing to
    # show. Entity updates arrive as `kind: "operation"`; the old `entity`
    # document kind is gone. A plan with entries always does: an entry that
    # cannot be described is rendered as undescribable, never as nothing,
    # because the server is gating the write on it either way.
    def render?
      operation? && entries.any?
    end

    def entries
      @entries ||= plan.filter_map { |definition| entry_for(definition) }
    end

    def pending?     = state == :pending
    def applied?     = state == :applied
    def declined?    = state == :declined
    def superseded?  = state == :superseded

    def discard_path
      @discard_path.presence
    end

    def apply_data
      data = {
        action: "click->ai-assistant#applyProposal",
        "ai-assistant-reply-param": apply_reply,
        "proposal-apply": ""
      }
      data["ai-assistant-message-id-param"] = @message_id if @message_id.present?
      data
    end

    def breaking_changes?
      entries.any? { |entry| entry.rows.any?(&:breaking) }
    end

    def apply_reply
      plan_t("apply_reply")
    end

    # A breaking row is the one thing in the list worth reading first; a
    # footnote is the one thing worth reading last.
    def row_classes(row)
      return "text-text-muted" if row.note
      return "bg-warning-subtle text-warning ring-1 ring-warning/20" if row.breaking

      "text-text-secondary"
    end

    private

    def operation? = @proposal["kind"].to_s == "operation"

    def plan
      value = @proposal["plan"]
      value.is_a?(Array) ? value : []
    end

    def entry_for(definition)
      return nil unless definition.is_a?(Hash)

      rows = rows_of(definition).flat_map { |row| rows_for(row) }
      rows = [ unplannable_row(definition) ] if rows.empty?
      rows += [ omitted_row("rows_omitted", definition["omitted_rows"]) ].compact

      Entry.new(name: clip(definition["name"].to_s, 0), rows: rows)
    end

    # The server caps what it parks on the message — 50 rows an entry, 20
    # entries a choice-list bucket — so the panel has to say the list is partial
    # rather than let the admin read it as everything that will change.
    def omitted_row(key, count)
      count = count.to_i
      return nil unless count.positive?

      change_row(label: row_label(key, count: count), breaking: false, note: true)
    end

    # The server sets `unplannable` when it could not work out what applying
    # the document would do, and an entry whose every row was junk leaves the
    # panel in the same position. Both are still gating the write, so the admin
    # is told the change cannot be shown rather than handed an empty card to
    # approve.
    def unplannable_row(definition)
      change_row(label: row_label("unplannable"), breaking: breaking?(definition))
    end

    def rows_of(definition)
      value = definition["rows"]
      value.is_a?(Array) ? value : []
    end

    # One payload row can be worth several lines (an options change carries
    # additions, removals and renames together) but never zero: the only rows
    # discarded here are the ones that are not hashes at all.
    def rows_for(row)
      return [] unless row.is_a?(Hash)

      kind = row["kind"].to_s
      action = row["action"].to_s
      name = clip(row["name"].to_s, 0)

      return [ other_row(row) ] unless ACTIONS.fetch(kind, []).include?(action)
      return [ other_row(row) ] if NAMED.include?(kind) && name.blank?

      case kind
      when "identity" then identity_rows(row)
      when "attribute" then attribute_rows(row, action, name)
      when "attribute_removed" then [ plain_row(row, "attribute_removed", name) ]
      when "default_properties" then [ plain_row(row, "default_properties_modified", nil) ]
      else [ plain_row(row, "#{kind}_#{action}", name) ]
      end
    end

    # A kind/action pairing with no sentence of its own, or a named row with no
    # name to put in one. Named rather than dropped: the write is gated on this
    # row's existence, so silence here is a change approved unseen.
    def other_row(row)
      change_row(label: row_label("other"), breaking: breaking?(row))
    end

    def identity_rows(row)
      field = row["field"].to_s

      [
        change_row(
          label: row_label("identity_modified", field: field_label(field)),
          breaking: breaking?(row),
          pairs: [ value_pair(row, field) ]
        )
      ]
    end

    def attribute_rows(row, action, name)
      return [ attribute_added_row(row, name) ] if action == "added"

      field = row["field"].to_s
      return options_rows(row, name) if field == "options"

      [
        change_row(
          label: row_label("attribute_modified", name: name, field: attribute_field_label(row, field)),
          breaking: breaking?(row),
          pairs: [ value_pair(row, field) ]
        )
      ]
    end

    # A `config` row is about one setting inside the config blob, and naming
    # that setting tells the admin more than naming the blob does.
    def attribute_field_label(row, field)
      field == "config" ? config_field_label(row) : field_label(field)
    end

    # A new field has no "before", so its type is shown on its own rather than
    # as one side of a change.
    def attribute_added_row(row, name)
      type = row["html_type"]

      change_row(
        label: row_label("attribute_added", name: name),
        breaking: breaking?(row),
        pairs: blank_value?(type) ? [] : [ [ nil, clip(value_label(type, "html_type"), 0) ] ]
      )
    end

    # One payload row can be worth three lines: the same change can add
    # options, drop others, and rename the ones that stayed.
    def options_rows(row, name)
      listed = [
        options_row(row, name, "added", values: option_values(row["added"])),
        options_row(row, name, "removed", values: option_values(row["removed"])),
        options_row(row, name, "relabelled", pairs: option_pairs(row["relabelled"]))
      ].compact
      # Every bucket empty (or unusable) still means the choice list is part of
      # what is being approved, so the row says so without listing anything.
      listed = [ options_unlisted_row(row, name) ] if listed.empty?

      listed + [ omitted_row("options_omitted", row["omitted"]) ].compact
    end

    def options_unlisted_row(row, name)
      change_row(
        label: row_label("attribute_modified", name: name, field: field_label("options")),
        breaking: breaking?(row)
      )
    end

    def options_row(row, name, change, values: [], pairs: [])
      return nil if values.empty? && pairs.empty?

      change_row(
        label: row_label("attribute_options_#{change}", name: name),
        breaking: breaking?(row),
        values: values,
        pairs: pairs
      )
    end

    def option_values(value)
      return [] unless value.is_a?(Array)

      value.filter_map { |option| option_text(option)&.then { |text| clip(text, 0) } }
    end

    # An option is a label, but the payload is model output: a blank one is
    # dropped rather than rendered as an empty chip, and a structured one is
    # worded rather than inspected. Left at full length — a relabel is clipped
    # as a pair, so that the clip cannot hide which part of it changed.
    def option_text(option)
      return nil if blank_value?(option) || (option.respond_to?(:empty?) && option.empty?)

      structured_label(option).strip.presence
    end

    # A relabel is matched by option value, so both sides always carry a label.
    # An entry missing one of them describes nothing and is dropped rather than
    # rendered as a chip with no text in it.
    def option_pairs(value)
      return [] unless value.is_a?(Array)

      value.filter_map do |pair|
        next unless pair.is_a?(Hash)

        before = option_text(pair["before"])
        after = option_text(pair["after"])
        next if before.nil? || after.nil?

        distinguish(before, after)
      end
    end

    def plain_row(row, key, name)
      change_row(label: row_label(key, name: name), breaking: breaking?(row))
    end

    def change_row(label:, breaking:, values: [], pairs: [], note: false)
      Row.new(label: label, breaking: breaking, values: values, pairs: pairs, note: note)
    end

    def value_pair(row, field)
      distinguish(value_label(row["before"], field), value_label(row["after"], field))
    end

    # Both sides are cut down so one option label or formula cannot take over
    # the panel — but never so far that two different values read as the same
    # one. When they agree for longer than the window, the window moves to
    # where they part company.
    def distinguish(before, after)
      offset = before == after ? 0 : divergence(before, after)

      [ clip(before, offset), clip(after, offset) ]
    end

    def divergence(before, after)
      shared = [ before.length, after.length ].min
      index = (0...shared).find { |position| before[position] != after[position] } || shared
      return 0 if index < MAX_VALUE_LENGTH

      # Centred, so the characters on both sides of the difference are readable.
      index - (MAX_VALUE_LENGTH / 2)
    end

    def clip(value, offset)
      return value if offset.zero? && value.length <= MAX_VALUE_LENGTH

      head = offset.positive? ? ELLIPSIS : ""
      tail = value.length > offset + MAX_VALUE_LENGTH ? ELLIPSIS : ""

      "#{head}#{value[offset, MAX_VALUE_LENGTH]}#{tail}"
    end

    def row_label(key, **arguments)
      plan_t("rows.#{key}", **arguments)
    end

    def field_label(field)
      return plan_t("field_other") unless FIELDS.include?(field)

      plan_t("fields.#{field}")
    end

    def config_field_label(row)
      key = row["config_key"].to_s
      return field_label("config") if key.blank?

      config_key_label(key)
    end

    def config_key_label(key)
      return plan_t("config_field_other") unless CONFIG_FIELDS.include?(key)

      plan_t("config_fields.#{key}")
    end

    # Every value arrives raw, so each shape is worded here. Rendering any of
    # them with `to_s` is what put a literal Ruby hash on screen — identical in
    # both locales — which is the review finding this dispatch exists to fix.
    def value_label(value, field)
      case field
      when "visibility", "validator_apply" then audiences_label(value)
      when "validators"                    then validators_label(value)
      when "options_source"                then options_source_label(value)
      when "readonly"                      then boolean_label(value)
      when "html_type"                     then html_type_label(value)
      when "type", "storage"               then enum_label(value, field)
      else structured_label(value)
      end
    end

    # The fallback arm of the dispatch above, and the reason it cannot be
    # `to_s`: a `config` row's value is whatever the schema lets that key hold,
    # and `attributeConfig.filter` holds an object. `to_s` on a Hash is Ruby
    # `inspect` syntax — punctuation the admin never chose, byte-identical in
    # both locales.
    #
    # Total by construction: a Hash reads as its worded pairs, an Array as its
    # worded members, and everything else is a scalar, which words itself. No
    # shape reaches the screen as `inspect` output.
    def structured_label(value, depth = 0)
      case value
      when Hash then pairs_label(value, depth)
      when Array then list_label(value, depth)
      when TrueClass, FalseClass then boolean_label(value)
      else blank_value?(value) ? not_set : value.to_s
      end
    end

    # `label: value`, with the key worded from the config settings — a filter's
    # `slug`/`op`/`value` are config keys like any other. Operator tokens are
    # the mathematical ones the attribute editor offers (`>=`, `!=`), so they
    # read as themselves in either locale and get no keys of their own.
    def pairs_label(value, depth)
      return not_set if value.empty?
      return plan_t("deep_value") if depth >= MAX_VALUE_DEPTH

      join(
        value.map do |key, nested|
          plan_t("pair", label: config_key_label(key.to_s), value: structured_label(nested, depth + 1))
        end
      )
    end

    def list_label(value, depth)
      return not_set if value.empty?
      return plan_t("deep_value") if depth >= MAX_VALUE_DEPTH

      join(value.map { |nested| structured_label(nested, depth + 1) })
    end

    # An audience map (`{"admin" => true, "member" => false, ...}`) reduced to
    # the audiences it enables, worded from the labels the attribute editor
    # already uses rather than a second set of my own.
    #
    # The enabled test mirrors EntityAttributeAudience.enabled? (private there):
    # a missing key means enabled, only an explicit false disables.
    def audiences_label(value)
      return not_set if value.nil?
      return structured_label(value) unless value.is_a?(Hash)

      enabled = EntityAttributeAudience::AUDIENCES.select do |audience|
        value[audience] != false && value[audience.to_sym] != false
      end
      return plan_t("audiences_none") if enabled.empty?

      join(enabled.map { |audience| I18n.t("comp_admin.attribute_modal.#{audience}") })
    end

    # A sorted array of registry type keys. ValidatorRegistry already maps each
    # to maint_core.validators.* at call time, so the locale is not frozen.
    def validators_label(value)
      return not_set if value.nil?
      return structured_label(value) unless value.is_a?(Array)

      labels = value.map { |type| validator_label(type) }.reject(&:blank?)
      labels.empty? ? not_set : join(labels)
    end

    # The registry keys off a string, so a structured entry is worded here
    # rather than handed to it as `inspect` output.
    def validator_label(type)
      return structured_label(type) if type.is_a?(Hash) || type.is_a?(Array)

      ValidatorRegistry.validator_label(type)
    end

    # `{"kind" => "static"}`, or an entity binding. "static" is an English word in the payload, not a label.
    def options_source_label(value)
      return not_set if value.nil?
      return structured_label(value) unless value.is_a?(Hash)

      kind = value["kind"].to_s
      return plan_t("options_source.static") if kind == "static"

      entity = value["entity_name"].to_s.strip
      return plan_t("options_source.other", kind: kind) if kind != "entity" || entity.empty?

      plan_t("options_source.entity", entity: entity)
    end

    # `false` is a value, so it cannot go through blank_value? first.
    def boolean_label(value)
      return not_set if value.nil?
      return structured_label(value) unless [ true, false ].include?(value)

      plan_t("boolean.#{value}")
    end

    def html_type_label(value)
      return structured_label(value) unless scalar?(value)

      HtmlTypeOptions.label_for(value.to_s)
    end

    # Enum keys with no registry of translated labels of their own. An enum
    # value added upstream falls back to itself rather than to a missing key.
    def enum_label(value, field)
      return structured_label(value) unless scalar?(value)

      plan_t("values.#{field}.#{value}", default: value.to_s)
    end

    # A value worth handing to a registry that expects a string.
    def scalar?(value)
      !blank_value?(value) && !value.is_a?(Hash) && !value.is_a?(Array)
    end

    def join(parts)
      parts.join(plan_t("list_separator"))
    end

    def not_set = plan_t("none")

    def plan_t(key, **arguments)
      I18n.t("ai_assistant.assistant.plan.#{key}", **arguments)
    end

    # Not `blank?`: a `readonly` row flipping to false is a value, not an
    # absence, and "not set" would misreport it.
    def blank_value?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def breaking?(row)
      row["breaking"] == true
    end
  end
end
