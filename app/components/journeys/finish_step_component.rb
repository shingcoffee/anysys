# frozen_string_literal: true

module Journeys
  # The journey builder's fixed last row: where the journey ends, the record
  # from an earlier step or another page. It posts as the last
  # `journey[steps][]` hash, which StepParams reads as the finish; CSS shows
  # the picker for the checked destination. The record picker lists earlier
  # steps that cannot be skipped.
  class FinishStepComponent < ApplicationComponent
    KINDS = %w[record page].freeze

    def initialize(step:, catalog:, earlier_rows:, submitted: {})
      @step = step
      @catalog = catalog
      @earlier_rows = Array(earlier_rows).map { |row| row.to_h.symbolize_keys }
      @submitted = submitted.to_h
    end

    def field(name) = "#{StepRowComponent::FIELD}[#{name}]"
    def key_value = @step.key.presence || "finish"
    def kind = KINDS.include?(target["kind"]) ? target["kind"] : KINDS.first
    def kind_label(value) = value == "page" ? t("journeys.admin.finish_kind.page") : t("journeys.admin.finish_record_option")
    def record_choices = @earlier_rows.reject { |row| row[:optional] }.map { |row| [row[:name], row[:key]] }
    def finish_step = target["step"]
    def grouped_page_options = StepRowComponent.grouped_page_options(@catalog)
    def finish_message
      @submitted.fetch("finish_message", target["message"]).to_s
    end
    def message_hint_id = "journey-finish-message-hint"

    def page_id
      id = @submitted["finish_page_id"].to_s
      found = @catalog.pages.find { |page| page.id.to_s == id } if id.present?
      found&.id || @catalog.page_for(target["action_key"])&.id
    end

    private

    def target = @step.target.to_h
  end
end
