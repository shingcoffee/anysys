# frozen_string_literal: true

module AiAssistant
  # The live trace of one turn: one row per pipeline step, with a glyph that
  # says whether the step is in flight, finished or broken.
  #
  # It sits directly above a reply that is still being written, so it stays at
  # caption weight — the reply is the thing worth reading, not the scaffolding.
  #
  # Rendered into `Stream::DRAFT_STEPS_ID`, which is also this component's root
  # id: the draft bubble ships the slot empty and every progress broadcast
  # swaps this element's contents in by that id.
  class ProgressComponent < ApplicationComponent
    def initialize(steps:)
      @steps = Array(steps)
    end

    attr_reader :steps

    # An empty trace has nothing to announce; suppressing the whole element
    # keeps the draft bubble from reserving vertical space for it.
    def render?
      steps.any?
    end

    def steps_id
      AiAssistant::Stream::DRAFT_STEPS_ID
    end

    def region_label
      I18n.t("ai_assistant.assistant.progress.label")
    end

    def state_of(step)
      return "failed" if step.failed?
      return "done" if step.done?
      return "running" if step.running?

      "pending"
    end

    def label_classes(step)
      if step.failed?
        "text-danger"
      elsif step.running?
        "text-text-secondary"
      else
        "text-text-muted"
      end
    end

    # Server-supplied identifiers (an entity or page name), not UI wording, so
    # they travel untranslated next to the translated step label.
    def detail_of(step)
      step.detail.presence
    end
  end
end
