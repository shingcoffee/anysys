# frozen_string_literal: true

module AiAssistant
  # The assistant bubble that exists only while a turn is running.
  #
  # It is deliberately the same shape as a finished assistant
  # `MessageComponent`: same avatar, same author row, same body typography and
  # the same Markdown variant classes. When the turn ends and the real message
  # is appended in its place, nothing about the text reflows — only the caret
  # and the progress trace disappear.
  #
  # Everything below the author row is filled in by Turbo:
  #   * `Stream::DRAFT_STEPS_ID` receives `ProgressComponent`
  #   * `Stream::DRAFT_BODY_ID` receives the rendered Markdown of the reply so far
  class DraftMessageComponent < ApplicationComponent
    def draft_id
      AiAssistant::Stream::DRAFT_ID
    end

    def steps_id
      AiAssistant::Stream::DRAFT_STEPS_ID
    end

    def body_id
      AiAssistant::Stream::DRAFT_BODY_ID
    end

    def author_label
      I18n.t("ai_assistant.assistant.title")
    end

    # Borrowed rather than copied: the draft and the message it becomes must
    # resolve to the same typography, or the reply visibly jumps on swap.
    def body_classes
      [
        "w-full max-w-[min(92%,42rem)] text-[15px] leading-7 break-words",
        AiAssistant::MessageComponent::BUBBLE_MARKDOWN,
        AiAssistant::MessageComponent::DEFAULT_ASSISTANT_TONE
      ].join(" ")
    end
  end
end
