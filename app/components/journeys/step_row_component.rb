# frozen_string_literal: true

module Journeys
  # One page step of the journey builder's timeline; `step: nil` renders the
  # blank row the builder clones. CSS shows the step type, fill/repeat/optional
  # on every row but the lead (`data-step-lead`: the first row of a journey
  # that starts with a new record), and `data-step-mode` shows the fields the
  # row needs: a row set to edit a record (`update`) picks the earlier step
  # whose record its page edits, from pages that edit records; otherwise the
  # chosen page decides between filling locked inputs (`relate`) and starting
  # a new record (`create`). Rows post as `journey[steps][]` hashes: the
  # hidden key comes first so each row starts its own hash, and the checkboxes
  # have no hidden companion (absent means off), which would otherwise open a
  # new hash mid-row and shift values into the next step. Under the fields,
  # the page's "On submit" block (StepEffectsComponent); a row an earlier
  # step's processing may leave out (`conditional`, never the first row) says
  # which earlier steps' processing can.
  class StepRowComponent < ApplicationComponent
    FIELD = "journey[steps][]"
    KINDS = %w[add update].freeze

    def self.key_for(step, index) = step.key.presence || "step_#{index + 1}"

    # +updates_only+ hides and disables pages that don't edit records, except
    # the +kept+ one, so a refused choice still posts.
    def self.grouped_page_options(catalog, updates_only: false, kept: nil)
      catalog.groups.map do |group|
        label = group.entity&.display_label.presence || I18n.t("journeys.admin.page_group_none")
        [label, group.pages.map do |page|
          next [page.name, page.id] if !updates_only || page.id == kept || catalog.fit(page).updates

          [page.name, page.id, { disabled: true, hidden: true }]
        end]
      end
    end

    def self.hint_for(fit)
      parts = [
        fit.entity_label.presence || I18n.t("journeys.admin.page_group_none"),
        fit.audiences.map { |audience| I18n.t("journeys.audiences.#{audience}") }.join(I18n.t("support.array.words_connector")),
        I18n.t(fit.creates ? "journeys.admin.page_hint.adds_records" : "journeys.admin.page_hint.edits_only")
      ]
      if fit.inputs.any?
        fields = fit.inputs.map(&:label).join(I18n.t("support.array.words_connector"))
        parts << I18n.t("journeys.admin.page_hint.locks", fields: fields)
      end
      parts.join(I18n.t("journeys.admin.page_hint.separator"))
    end

    def initialize(step:, index:, catalog:, earlier_rows:, submitted: {}, lead: false)
      @step = step
      @index = index
      @lead = lead
      @catalog = catalog
      @earlier_rows = Array(earlier_rows).map { |row| row.to_h.symbolize_keys }
      @submitted = submitted.to_h
    end

    def field(name) = "#{FIELD}[#{name}]"
    def input_field(slug) = "#{FIELD}[inputs][#{slug}]"
    def template? = @step.nil?
    def lead? = @lead

    def key_value = template? ? "" : self.class.key_for(@step, @index)
    def label_value = @step&.label
    def grouped_page_options = self.class.grouped_page_options(@catalog, updates_only: update?, kept: page_id)
    def repeat? = @step&.repeat == true
    def optional? = @step&.optional == true
    def conditional? = @step&.conditional? == true

    # The earlier steps whose processing may leave this one out.
    def skipped_by_text
      by = @earlier_rows.select { |row| Array(row[:skips]).include?(key_value) }.map { |row| row[:name] }
      return t("journeys.admin.step_conditional_none") if by.empty?

      t("journeys.admin.step_conditional_by", steps: by.join(t("journeys.admin.effects.separators.list")))
    end

    def effects_component = StepEffectsComponent.new(catalog: @catalog, page: selected_page, updating: update?)
    # Step keys are unique in the form; the builder re-ids a cloned row by its new key.
    def hint_id = "journey-step-hint-#{key_value}"
    def hint_text
      page = selected_page
      page ? self.class.hint_for(@catalog.fit(page)) : ""
    end

    def update?
      kind = @submitted.key?("kind") ? @submitted["kind"].to_s : @step&.kind.to_s
      kind == "update" && !lead?
    end

    def kind_value = update? ? "update" : "add"
    def kind_options = KINDS.map { |kind| [t("journeys.admin.step_kind.#{kind}"), kind] }

    def step_mode
      return "update" if update?

      page = selected_page
      return "none" unless page

      @catalog.fit(page).inputs.any? ? "relate" : "create"
    end

    def fill_inputs
      page = selected_page
      page ? @catalog.fit(page).inputs : []
    end

    def input_choices(entity_id)
      @earlier_rows.select { |row| row[:entity_id].to_s == entity_id.to_s }.map { |row| [row[:name], row[:key]] }
    end

    def selected_input(field, entity_id)
      from = @step&.inputs.to_h[field.to_s].to_s.presence
      from if from && input_choices(entity_id).any? { |_, key| key == from }
    end

    # The record an update row edits: an earlier step of its page's type.
    def record_entity = selected_page && @catalog.fit(selected_page).entity_id.to_s
    def record_choices = record_entity.present? ? input_choices(record_entity) : []

    def selected_record
      from = (@submitted.key?("record") ? @submitted["record"] : @step&.record).to_s.presence
      from if from && record_choices.any? { |_, key| key == from }
    end

    def page_id
      selected_page&.id
    end

    private

    def selected_page
      return @selected_page if defined?(@selected_page)

      id = @submitted["page_id"].to_s
      found = @catalog.pages.find { |page| page.id.to_s == id } if id.present?
      @selected_page = found || @catalog.page_for(@step&.action_key)
    end
  end
end
