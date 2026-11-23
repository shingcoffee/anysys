# frozen_string_literal: true

module AiAssistant
  # Transcript + composer for one conversation.
  #
  # The thread it renders is chosen by the controller; "New chat" is owned by
  # ConversationListComponent, because starting a thread is a list operation
  # rather than a composer one.
  class AssistantPanelComponent < ApplicationComponent
    COMPOSER_ID = "ai_assistant_composer"
    HINT_ID = "ai_assistant_composer_hint"
    MENTION_MENU_ID = "ai_assistant_mention_menu"
    ERROR_ID = "ai_assistant_composer_error"

    # Client-side floor between two sends. The server's burst window
    # (AiAssistant::Limits::BURST) is the real guard; this only stops a held
    # Enter key from spending that budget on duplicate turns.
    COOLDOWN_MS = 1_200

    # How long the panel waits for any stream traffic after a send before it
    # decides the connection, not the model, is the problem. Generously longer
    # than a slow multi-step turn: a false positive here would tell the reader
    # their reply was lost while it is still being written.
    WATCHDOG_MS = 180_000

    PromptCard = Struct.new(:key, :label, :prompt, :icon, keyword_init: true)

    # Starter prompts shown on an empty thread, paired with the icon that hints
    # at what the assistant will touch.
    PROMPT_ICONS = {
      "create_entity" => "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75",
      "create_flowchart" => "M9 4.5h6a1.5 1.5 0 011.5 1.5v1.5A1.5 1.5 0 0115 9H9a1.5 1.5 0 01-1.5-1.5V6A1.5 1.5 0 019 4.5zM12 9v3m0 0H6.75A1.5 1.5 0 005.25 13.5V18a1.5 1.5 0 001.5 1.5h1.5A1.5 1.5 0 0010 18v-1.5m2-4.5h5.25a1.5 1.5 0 011.5 1.5V18a1.5 1.5 0 01-1.5 1.5h-1.5A1.5 1.5 0 0114.25 18v-1.5",
      "create_website" => "M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418",
      "new_page" => "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z",
      "enable_module" => "M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 01-.657.643 48.39 48.39 0 01-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 01-.658.664v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 00-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 01-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 00.657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 01-.349-1.003c0-1.035 1.007-1.875 2.25-1.875s2.25.84 2.25 1.875c0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 005.427-.63 48.05 48.05 0 00.582-4.717.532.532 0 00-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 00.658-.663 48.422 48.422 0 00-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 01-.61-.58v0z"
    }.freeze

    def initialize(messages:, customer_id:, user_id:, user_name:, conversation_id:, viewer: nil)
      @messages = Array(messages)
      @customer_id = customer_id
      @user_id = user_id
      @user_name = user_name
      @conversation_id = conversation_id
      @viewer = viewer
    end

    attr_reader :messages, :customer_id, :user_id, :user_name, :conversation_id

    def composer_id = COMPOSER_ID

    def hint_id = HINT_ID

    def mention_menu_id = MENTION_MENU_ID

    def error_id = ERROR_ID

    def draft_id = AiAssistant::Stream::DRAFT_ID

    def messages_url
      helpers.admin_modules_ai_assistant_messages_path(customer_id)
    end

    def mentions_url
      helpers.mentions_admin_modules_ai_assistant_messages_path(customer_id)
    end

    def stop_url
      helpers.stop_admin_modules_ai_assistant_messages_path(customer_id)
    end

    def regenerate_url
      helpers.regenerate_admin_modules_ai_assistant_messages_path(customer_id)
    end

    # Rounds already spent, counted from the turns already on the page so the
    # panel does not issue a second query for something it is holding.
    def user_turns
      @user_turns ||= messages.count(&:user?)
    end

    def turns_remaining
      AiAssistant::Limits.turns_remaining(user_turns)
    end

    def turns_exhausted?
      AiAssistant::Limits.turns_exhausted?(user_turns)
    end

    # Only surfaced near the cap: a counter on every thread would be noise.
    def turns_hint
      return I18n.t("ai_assistant.assistant.turns_exhausted") if turns_exhausted?
      return nil unless AiAssistant::Limits.turns_warning?(user_turns)

      I18n.t("ai_assistant.assistant.turns_remaining", count: turns_remaining)
    end

    def composer_placeholder
      return I18n.t("ai_assistant.assistant.turns_exhausted") if turns_exhausted?

      I18n.t("ai_assistant.assistant.placeholder")
    end

    # Regeneration replays the last user turn, so it is only offered once there
    # is one and the thread still has budget to spend on it.
    def regeneratable?
      messages.any?(&:user?) && !turns_exhausted?
    end

    # The menu rows are built client-side from the mentions endpoint, so the
    # kind badge has to travel as a translated label map.
    def mention_kinds
      AiAssistant::Assistant::Mentions.kinds_for(viewer: @viewer).index_with do |kind|
        I18n.t("ai_assistant.assistant.mention_kinds.#{kind}")
      end
    end

    def mention_hint
      if flowchart_visible?
        I18n.t("ai_assistant.assistant.mention_hint")
      else
        I18n.t("ai_assistant.assistant.mention_hint_without_flowchart")
      end
    end

    # Thread traffic (bubbles, draft, status, artifact) for this conversation.
    def stream_name
      AiAssistant::Stream.name(
        customer_id: customer_id,
        user_id: user_id,
        conversation_id: conversation_id
      )
    end

    # Traffic that outlives one thread: mic transcripts and the chat sidebar.
    def user_stream_name
      AiAssistant::Stream.user_name(customer_id: customer_id, user_id: user_id)
    end

    def empty?
      messages.empty?
    end

    # Only the newest pending proposal is actionable. ReplyWriter now retires
    # older offers to `superseded_proposal` before parking a new one, so a
    # reloaded thread should have at most one `pending_confirmation`. The
    # in-memory pick stays as a belt: a live DOM can still hold two pending
    # panels until JS supersedes them, and a replace of an older bubble must
    # not revive Apply on it.
    def active_proposal_message_id
      return @active_proposal_message_id if defined?(@active_proposal_message_id)

      @active_proposal_message_id = messages
                                    .reverse_each
                                    .find { |message| message.metadata_json["pending_confirmation"].is_a?(Hash) }
                                    &.id
    end

    def proposal_active?(message)
      active_proposal_message_id.present? && message.id == active_proposal_message_id
    end

    def questions_active?(message)
      message.id == messages.last&.id
    end

    def greeting
      I18n.t("ai_assistant.assistant.greeting", name: user_name.presence || I18n.t("ai_assistant.assistant.title"))
    end

    def prompts
      prompt_cards.map(&:prompt)
    end

    def prompt_cards
      PROMPT_ICONS.filter_map do |key, icon|
        next if key == "create_flowchart" && !flowchart_visible?
        next if key == "create_website" && !website_enabled?

        PromptCard.new(
          key: key,
          label: I18n.t("ai_assistant.assistant.prompt_labels.#{key}"),
          prompt: I18n.t("ai_assistant.assistant.prompts.#{key}"),
          icon: icon
        )
      end
    end

    def welcome
      @welcome ||= AiAssistant::Assistant::WelcomePrompts.call(customer_id: customer_id, messages: messages)
    end

    def recent_chips
      welcome.chips
    end

    def attachment_rules
      AiAssistant::Assistant::Attachments
    end

    def attachments_allowed?
      attachment_rules.supported?
    end

    def stimulus_data
      {
        controller: "ai-assistant",
        ai_assistant_url_value: messages_url,
        ai_assistant_stop_url_value: stop_url,
        ai_assistant_regenerate_url_value: regenerate_url,
        ai_assistant_mentions_url_value: mentions_url,
        ai_assistant_conversation_id_value: conversation_id.to_s,
        ai_assistant_mention_kinds_value: mention_kinds.to_json,
        ai_assistant_mention_empty_label_value: I18n.t("ai_assistant.assistant.mention_empty"),
        ai_assistant_turns_remaining_value: turns_remaining,
        ai_assistant_turns_warning_at_value: AiAssistant::Limits::TURNS_WARNING_THRESHOLD,
        ai_assistant_cooldown_ms_value: COOLDOWN_MS,
        ai_assistant_watchdog_ms_value: WATCHDOG_MS,
        ai_assistant_turns_remaining_template_value: I18n.t("ai_assistant.assistant.turns_remaining_template"),
        ai_assistant_turns_exhausted_label_value: I18n.t("ai_assistant.assistant.turns_exhausted"),
        ai_assistant_max_files_value: attachment_rules::MAX_FILES,
        ai_assistant_max_bytes_value: attachment_rules::MAX_BYTES,
        ai_assistant_accept_value: attachment_rules.accept,
        ai_assistant_too_many_template_value: I18n.t("ai_assistant.assistant.too_many_images_template"),
        ai_assistant_type_label_value: I18n.t("ai_assistant.errors.invalid_image_type"),
        ai_assistant_size_template_value: I18n.t("ai_assistant.assistant.image_too_large_template"),
        ai_assistant_size_label_value: I18n.t("ai_assistant.assistant.image_size_label"),
        ai_assistant_max_total_bytes_value: attachment_rules::MAX_TOTAL_BYTES,
        ai_assistant_total_size_label_value: I18n.t("ai_assistant.errors.images_too_large_total"),
        ai_assistant_stop_label_value: I18n.t("ai_assistant.assistant.stop"),
        ai_assistant_stopping_label_value: I18n.t("ai_assistant.assistant.status.stopping"),
        ai_assistant_copy_label_value: I18n.t("ai_assistant.assistant.copy"),
        ai_assistant_copied_label_value: I18n.t("ai_assistant.assistant.copied"),
        ai_assistant_copy_failed_label_value: I18n.t("ai_assistant.assistant.copy_failed"),
        ai_assistant_send_failed_label_value: I18n.t("ai_assistant.assistant.send_failed"),
        ai_assistant_regenerate_failed_label_value: I18n.t("ai_assistant.assistant.regenerate_failed"),
        ai_assistant_stop_failed_label_value: I18n.t("ai_assistant.assistant.stop_failed"),
        ai_assistant_connection_lost_label_value: I18n.t("ai_assistant.assistant.connection_lost"),
        ai_assistant_remove_image_label_value: I18n.t("ai_assistant.assistant.remove_image"),
        ai_assistant_remove_mark_value: I18n.t("ai_assistant.assistant.remove_image_mark"),
        ai_assistant_proposal_apply_label_value: I18n.t("ai_assistant.assistant.plan.apply"),
        ai_assistant_proposal_applying_label_value: I18n.t("ai_assistant.assistant.plan.applying"),
        ai_assistant_proposal_superseded_label_value: I18n.t("ai_assistant.assistant.plan.superseded"),
        ai_assistant_questions_send_label_value: I18n.t("ai_assistant.assistant.questions.send"),
        ai_assistant_questions_sending_label_value: I18n.t("ai_assistant.assistant.questions.sending")
      }
    end

    private

    def flowchart_visible?
      FlowchartVisibility.allowed?(@viewer)
    end

    def website_enabled?
      FeatureModules::Website::Registration.enabled_for?(customer_id)
    end
  end
end
