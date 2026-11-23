# frozen_string_literal: true

module Journeys
  # Where a journey begins, above the builder's step timeline: with a new
  # record (the first page creates it), with a new user account (an admin
  # creates it on Authentication › Users › New, then the first page creates
  # the person record linked to it), or with an existing record of a chosen
  # type, which admins or members open from that record's page — optionally
  # only records whose choice field holds one of the chosen values
  # (`condition`, a record step's `when`). Posts as `journey[start]`; the
  # builder controller reads it to mark the lead row, to offer the start
  # record to the fill and finish pickers, and to swap in the chosen record
  # type's choice fields (`choices`, BuilderCatalog#choices). Each condition
  # value notes the other journeys' steps that leave records in it.
  class StartStepComponent < ApplicationComponent
    KINDS = %w[create user record].freeze
    FIELD = "journey[start]"
    VALUE_CLASS = "inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-lg border border-border-subtle bg-surface px-3 " \
                  "text-sm text-text-primary transition-base hover:bg-surface-hover has-[:checked]:border-accent has-[:checked]:bg-accent-subtle"

    attr_reader :kind, :entity_id, :key

    def initialize(kind:, entity_id:, key:, record_types:, condition: nil, choices: {})
      @kind = kind
      @entity_id = entity_id.to_s
      @key = key
      @record_types = Array(record_types)
      @condition = condition.is_a?(Hash) ? condition.stringify_keys : {}
      @choices = choices.to_h
    end

    def field(name) = "#{FIELD}[#{name}]"
    def kind_label(value) = t("journeys.admin.start.kinds.#{value}")
    def entity_options = @record_types.map { |entity| [entity.display_label, entity.id] }

    def kind_data(value)
      data = { journey_builder_target: "startKind", action: "change->journey-builder#refresh" }
      case value
      when "record" then data.merge(start_record: true)
      when "user" then data.merge(start_user: true)
      else data
      end
    end

    def when_field = @condition["field"].to_s
    def when_values = Array(@condition["in"]).map(&:to_s)
    def when_field_name = "#{FIELD}[when][field]"

    # One value the condition may accept; the builder clones a blank one
    # (`whenValueTemplate`) for each option of a newly chosen field.
    def value_choice(label, value, sources = "")
      checked = value.present? && when_values.include?(value)
      box = check_box_tag("#{FIELD}[when][in][]", value, checked, id: nil, class: "size-4 shrink-0 rounded border-border accent-accent",
                                                                  data: { when_value: true })
      note = tag.span(sources, class: "text-xs text-text-muted empty:hidden", data: { when_value_sources: true })
      tag.label(class: VALUE_CLASS) do
        safe_join([box, tag.span(class: "flex min-w-0 flex-col py-1") { safe_join([tag.span(label, data: { when_value_label: true }), note]) }])
      end
    end

    # The record type's choice fields; a saved field it no longer offers
    # stays listed so saving again keeps it.
    def field_options
      list = entity_choices.map { |choice| [choice.label, choice.field] }
      list << [when_field, when_field] if when_field.present? && list.none? { |_, field| field == when_field }
      list
    end

    # The chosen field's values, plus any saved value it no longer offers, each
    # with where other journeys leave records in it.
    def value_options
      options = entity_choices.find { |choice| choice.field == when_field }&.options.to_a
                              .map { |option| [option.label, option.value, reached_in(option.sources)] }
      options + (when_values - options.map(&:second)).map { |value| [value, value, ""] }
    end

    # "Reached in …" under a condition value, or "" when no other journey
    # leaves records in it.
    def self.reached_in(sources) = sources.present? ? I18n.t("journeys.admin.handoffs.reached_in", sources: sources) : ""
    def reached_in(sources) = self.class.reached_in(sources)

    def values_hidden? = when_field.blank?

    private

    def entity_choices = Array(@choices[@entity_id])
  end
end
