# frozen_string_literal: true

module AiAssistant
  # Structured questions parked on an assistant turn. The card is open only
  # for the newest message; older ones render closed. The client may flip an
  # open card to `data-questions="held"` while the answer is in flight, then
  # close it in place from the markup already on the page.
  class ClarifyingQuestionsComponent < ApplicationComponent
    STATES = %i[open closed].freeze
    TYPES = %w[single multiple text].freeze

    CHIP_OPEN = [
      "inline-flex max-w-full cursor-pointer items-center rounded-full bg-surface px-3.5 py-1.5",
      "text-left text-sm leading-5 text-text-secondary ring-1 ring-border-subtle transition-base",
      "min-h-9 whitespace-normal break-words pointer-coarse:min-h-11",
      "hover:bg-accent-subtle hover:text-accent hover:ring-accent-muted",
      "peer-checked:bg-accent-subtle peer-checked:font-medium peer-checked:text-accent-text peer-checked:ring-accent-muted",
      "peer-focus-visible:outline-none peer-focus-visible:ring-2 peer-focus-visible:ring-accent",
      "peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-canvas",
      "peer-disabled:cursor-not-allowed peer-disabled:opacity-50"
    ].join(" ").freeze

    CHIP_CLOSED = [
      "max-w-full rounded-full bg-surface px-3 py-1 text-xs leading-5 text-text-muted",
      "ring-1 ring-border-subtle whitespace-normal break-words"
    ].join(" ").freeze

    NUMBER_BADGE = [
      "flex size-5 shrink-0 items-center justify-center rounded-full bg-surface",
      "text-2xs font-semibold tabular-nums text-text-secondary ring-1 ring-border-subtle"
    ].join(" ").freeze

    attr_reader :state

    def initialize(questions:, state: :open)
      @questions = questions
      @state = STATES.include?(state) ? state : :open
    end

    def render?
      usable_questions.any?
    end

    def open?
      state == :open
    end

    def closed?
      state == :closed
    end

    def usable_questions
      @usable_questions ||= Array(@questions).filter_map { |row| usable_question(row) }
    end

    def show_numbers?
      usable_questions.size > 1
    end

    def number_for(question, index)
      digits = question["id"].to_s[/\d+/]
      digits ? digits.to_i : index + 1
    end

    def field_name(question)
      "ai_assistant_question_#{object_id}_#{question["id"]}"
    end

    def legend_id(question)
      "ai-assistant-question-#{object_id}-#{question["id"]}"
    end

    def other_id(question)
      "#{legend_id(question)}-other"
    end

    def option_selected?(question, option)
      default = question["default"]
      if question["type"] == "multiple"
        selected_list(default).any? { |item| item.to_s == option }
      else
        default.to_s == option
      end
    end

    def text_default(question)
      default = question["default"]
      default.is_a?(String) ? default : ""
    end

    def choice?(question)
      question["type"] == "single" || question["type"] == "multiple"
    end

    def card_data
      {
        controller: "ai-assistant-questions",
        questions: state,
        action: "ai-assistant-questions:answer->ai-assistant#answerQuestions",
        ai_assistant_questions_no_preference_value: I18n.t("ai_assistant.assistant.questions.no_preference"),
        ai_assistant_questions_list_separator_value: I18n.t("ai_assistant.assistant.plan.list_separator"),
        ai_assistant_questions_skip_reply_value: I18n.t("ai_assistant.assistant.questions.skip_reply")
      }
    end

    private

    def usable_question(row)
      return nil unless row.is_a?(Hash)

      prompt = row["prompt"].to_s.strip
      return nil if prompt.blank?

      type = row["type"].to_s
      return nil unless TYPES.include?(type)

      options = row.key?("options") ? row["options"] : []
      return nil unless options.is_a?(Array)

      {
        "id" => row["id"].to_s.presence || "q",
        "prompt" => prompt,
        "type" => type,
        "options" => options.select { |option| option.is_a?(String) && option.present? },
        "default" => row["default"]
      }
    end

    def selected_list(default)
      return default if default.is_a?(Array)
      return [ default ] if default.is_a?(String) && default.present?

      []
    end
  end
end
