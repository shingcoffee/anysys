# frozen_string_literal: true

module AiAssistant
  # The chat switcher for the assistant workspace: a left-side slide-over,
  # collapsed off-canvas at every width until the reader opens it.
  #
  # ---------------------------------------------------------------------------
  # Stimulus contract — `ai-assistant-conversations`
  # ---------------------------------------------------------------------------
  # This component only emits attributes; `app/javascript/**` belongs to the
  # JS lane. The controller it is written against must implement:
  #
  #   Values (on the root element)
  #     createUrlValue     String  POST here to start a chat
  #     baseUrlValue       String  collection URL, for building member URLs
  #     panelIdValue       String  id of the slide-over panel
  #     renameLabelValue   String  accessible label for the rename input
  #     saveLabelValue     String  submit label for the inline rename form
  #     cancelLabelValue   String  dismiss label for the inline rename form
  #     failedLabelValue   String  error copy for any failed write

  #   Targets
  #     panel         the left slide-over (off-canvas via `-translate-x-full`)
  #     backdrop      the dimmed scrim behind the slide-over
  #     row           one chat row (carries `data-conversation-id`)
  #     alert         the error slot, hidden until a write fails
  #     deleteDialog  the confirmation dialog `destroy` opens
  #     toggle        the toolbar control that opens and closes the slide-over
  #
  #   Actions and their params
  #     create         —                                          POST   createUrl
  #     rename         idParam, urlParam, titleParam              PATCH  urlParam
  #     archive        idParam, urlParam, archivedParam (Boolean) POST   urlParam
  #     destroy        idParam, urlParam                          opens deleteDialog
  #     confirmDestroy —                                          DELETE urlParam
  #     cancelDestroy  —                                          dismisses the dialog
  #     toggle         —                                          opens/closes the slide-over
  #     close          —                                          dismisses the slide-over
  #                    (backdrop click, Escape, and the panel close control)
  #
  # `create` is also bound to `ai-assistant:newChat@window`, so the composer can
  # ask for a new chat from outside this element once a thread is spent.
  #
  # The server re-renders this whole component over Turbo after every write
  # (`Stream.broadcast_conversations`), so the controller never has to patch
  # the DOM itself — it fires the request and lets the stream settle the list.
  class ConversationListComponent < ApplicationComponent
    PANEL_ID = "ai_assistant_conversations_panel"
    TOGGLE_ID = "ai_assistant_conversations_toggle"
    ALERT_ID = "ai_assistant_conversations_alert"
    NEW_HINT_ID = "ai_assistant_conversations_new_hint"
    HEADING_ID = "ai_assistant_conversations_heading"
    DELETE_DIALOG_ID = "ai_assistant_conversations_delete_dialog"

    # Archived threads are a recovery aid, not a browsing surface: past a
    # couple of dozen the disclosure becomes its own scrolling problem, and
    # Conversation::MAX_PER_USER already caps the total a user can accumulate.
    ARCHIVED_LIMIT = 20

    attr_reader :customer, :user, :current_id

    def initialize(customer:, user:, current_id: nil)
      @customer = customer
      @user = user
      @current_id = current_id
    end

    def list_id
      AiAssistant::Stream::CONVERSATIONS_ID
    end

    def panel_id = PANEL_ID

    def toggle_id = TOGGLE_ID

    def alert_id = ALERT_ID

    def new_hint_id = NEW_HINT_ID

    def heading_id = HEADING_ID

    def delete_dialog_id = DELETE_DIALOG_ID

    def delete_dialog_title_id = "#{DELETE_DIALOG_ID}_title"

    def delete_dialog_body_id = "#{DELETE_DIALOG_ID}_body"

    def conversations
      @conversations ||= AiAssistant::Conversation.owned_by(customer: customer, user: user)
    end

    def active_conversations
      @active_conversations ||= AiAssistant::Conversation.preload_fallback_titles(
        conversations.active.recent_first.to_a
      )
    end

    def archived_conversations
      @archived_conversations ||= AiAssistant::Conversation.preload_fallback_titles(
        conversations.archived.recent_first.limit(ARCHIVED_LIMIT).to_a
      )
    end

    def any_active?
      active_conversations.any?
    end

    def any_archived?
      archived_conversations.any?
    end

    def current?(conversation)
      current_id.present? && conversation.id.to_s == current_id.to_s
    end

    # The thread the workspace has open. Falls back to the most recently active
    # one because Stream.broadcast_conversations re-renders this list without a
    # current id, and that is the thread the page would open on a reload.
    def current_conversation
      return @current_conversation if defined?(@current_conversation)

      @current_conversation =
        if current_id.present?
          active_conversations.find { |row| current?(row) }
        else
          active_conversations.first
        end
    end

    # An empty thread already is a new chat, so offering to start another only
    # accumulates identical blank rows. StartConversation refuses it too — this
    # just stops the button asking for something it cannot have.
    def new_disabled?
      current_conversation.present? && current_conversation.empty?
    end

    def new_hint
      return nil unless new_disabled?

      I18n.t("ai_assistant.errors.current_chat_empty")
    end

    # Wayfinding in the toolbar: which thread the transcript below belongs to.
    def current_heading
      current_conversation.present? ? title_of(current_conversation) : I18n.t("ai_assistant.assistant.conversations.untitled")
    end

    def collection_url
      helpers.admin_modules_ai_assistant_conversations_path(customer.id)
    end

    def member_url(conversation)
      helpers.admin_modules_ai_assistant_conversation_path(customer.id, conversation)
    end

    def archive_url(conversation)
      helpers.archive_admin_modules_ai_assistant_conversation_path(customer.id, conversation)
    end

    def open_url(conversation)
      helpers.admin_assistant_path(customer.id, conversation: conversation.id)
    end

    def assistant_path
      helpers.admin_assistant_path(customer.id)
    end

    def title_of(conversation)
      conversation.display_title
    end

    def timestamp_of(conversation)
      at = conversation.last_active_at || conversation.updated_at
      return nil if at.blank?

      I18n.t("chrome.admin_table.time_ago", time: helpers.time_ago_in_words(at))
    end


    def iso_timestamp_of(conversation)
      at = conversation.last_active_at || conversation.updated_at
      at&.iso8601
    end

    def row_classes(conversation)
      base = "flex min-h-10 w-full items-center gap-2 rounded-lg py-2 pl-2.5 pr-10 transition-base " \
             "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent pointer-coarse:min-h-11"
      if current?(conversation)
        "#{base} bg-accent-subtle text-accent-text ring-1 ring-accent-muted/60"
      else
        "#{base} text-text-secondary hover:bg-surface-hover hover:text-text-primary"
      end
    end

    def action_params(conversation, url)
      {
        ai_assistant_conversations_id_param: conversation.id,
        ai_assistant_conversations_url_param: url
      }
    end

    def stimulus_data
      {
        controller: "ai-assistant-conversations",
        # The composer is not inside this element, so its "Start a new chat"
        # escape hatch has to reach the list as an event.
        action: "ai-assistant:newChat@window->ai-assistant-conversations#create",
        ai_assistant_conversations_create_url_value: collection_url,
        ai_assistant_conversations_base_url_value: collection_url,
        ai_assistant_conversations_panel_id_value: panel_id,
        ai_assistant_conversations_rename_label_value: I18n.t("ai_assistant.assistant.conversations.rename_label"),
        ai_assistant_conversations_save_label_value: I18n.t("ai_assistant.assistant.conversations.save"),
        ai_assistant_conversations_cancel_label_value: I18n.t("ai_assistant.assistant.conversations.cancel"),
        ai_assistant_conversations_failed_label_value: I18n.t("ai_assistant.assistant.conversations.failed")
      }
    end
  end
end
