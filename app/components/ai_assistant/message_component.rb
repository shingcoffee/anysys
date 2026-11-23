# frozen_string_literal: true

module AiAssistant
  class MessageComponent < ApplicationComponent
    BUBBLE_MARKDOWN = "[&>*+*]:mt-2.5 [&_a]:text-accent [&_a]:underline [&_a]:underline-offset-2 [&_code]:rounded-md [&_code]:bg-canvas [&_code]:px-1 [&_li]:ml-5 [&_li]:pl-0.5 [&_li+li]:mt-1 [&_li]:marker:text-text-muted [&_ol]:list-decimal [&_pre]:overflow-x-auto [&_pre]:rounded-xl [&_pre]:bg-canvas [&_pre]:p-3 [&_strong]:font-semibold [&_strong]:text-text-primary [&_ul]:list-disc"
    DEFAULT_ASSISTANT_TONE = "text-text-primary"
    ASSISTANT_TONES = {
      "failed" => "w-full max-w-[min(92%,42rem)] rounded-xl bg-danger-subtle/80 px-3.5 py-2 text-sm leading-6 text-danger ring-1 ring-danger/10",
      "cancelled" => "rounded-2xl bg-canvas px-4 py-2.5 text-text-muted ring-1 ring-border-subtle"
    }.freeze
    UNDO_ICON = "M9 15L3 9m0 0l6-6M3 9h12a6 6 0 010 12h-3"
    BUILD_BADGES = {
      "running" => :primary,
      "waiting_for_answers" => :warning,
      "finished" => :success,
      "failed" => :danger,
      "cancelled" => :default
    }.freeze

    attr_reader :message

    # `proposal_active` defaults to true because Stream.broadcast_message
    # renders this component standalone for a freshly appended reply, which is
    # by definition the newest proposal in the thread. The panel overrides it
    # when it replays an older turn that has since been superseded.
    # `questions_active` defaults to nil so a standalone render (broadcast,
    # Turbo replace) can decide from the conversation: open only when no later
    # message exists. The panel passes an explicit boolean when it already
    # knows which turn is last. The later-message query runs only when this
    # turn actually carries questions.
    def initialize(message:, proposal_active: true, questions_active: nil, undo_errors: [])
      @message = message
      @proposal_active = proposal_active
      @questions_active = questions_active
      @undo_errors = Array(undo_errors)
    end

    attr_reader :undo_errors

    # :available, :undone, or nil for a reply that wrote nothing to the website.
    # An undo is not offered while the Website module is off, since it would
    # be refused.
    def website_undo_state
      return @website_undo_state if defined?(@website_undo_state)

      state = Websites::Assistant::Undo.state(message) unless user?
      state = nil if state == :available && !FeatureModules::Website::Registration.enabled_for?(message.customer_id)
      @website_undo_state = state
    end

    def undo_path
      helpers.undo_admin_modules_ai_assistant_message_path(message.customer_id, message)
    end

    def undo_error_text
      undo_errors.join(I18n.t("ai_assistant.assistant.website.sentence_separator"))
    end

    def user?
      message.user?
    end

    def bubble_classes
      if user?
        "w-fit max-w-[min(88%,34rem)] rounded-2xl rounded-br-md bg-accent-subtle px-4 py-2.5 text-sm leading-6 text-accent-text ring-1 ring-accent-muted/70 whitespace-pre-line break-words"
      else
        tone = ASSISTANT_TONES.fetch(message.status, DEFAULT_ASSISTANT_TONE)
        "w-full max-w-[min(92%,42rem)] text-[15px] leading-7 break-words #{BUBBLE_MARKDOWN} #{tone}"
      end
    end

    # Composer input can carry stray leading/trailing whitespace, which
    # `whitespace-pre-line` would otherwise render as blank lines in the bubble.
    def body_text
      message.body.to_s.strip
    end

    def author_label
      user? ? I18n.t("ai_assistant.assistant.you") : I18n.t("ai_assistant.assistant.title")
    end

    def timestamp_label
      I18n.l(message.created_at, format: :short)
    end

    def body_html
      AiAssistant::Assistant::Markdown.render(message.body)
    end

    def images
      message.images.attached? ? message.images : []
    end

    def changes
      Array(message.metadata_json["changes"]).select { |row| row.is_a?(Hash) && row["name"].present? }
    end

    # Forms the reply generated, re-read so a page deleted, taken offline or
    # narrowed since the reply was written no longer offers a dead link.
    def page_links
      return @page_links if defined?(@page_links)
      return @page_links = [] if user?

      ids = Array(message.metadata_json["page_links"]).filter_map do |row|
        Integer(row["id"].to_s, exception: false) if row.is_a?(Hash)
      end
      return @page_links = [] if ids.empty?

      pages = Page.where(customer_id: message.customer_id, id: ids).index_by(&:id)
      @page_links = ids.uniq.filter_map { |id| pages[id] }.select { |page| page.launched? && page.visible_to?(:admin) }
    end

    def page_form_path(page)
      helpers.admin_maintenance_page_preview_path(message.customer_id, page)
    end

    def questions
      return [] if user?

      value = message.metadata_json["questions"]
      value.is_a?(Array) ? value : []
    end

    def assumptions
      return [] if user?

      value = message.metadata_json["assumptions"]
      return [] unless value.is_a?(Array)

      value.select { |item| item.is_a?(String) && item.strip.present? }.first(5)
    end

    def questions_state
      questions_open? ? :open : :closed
    end

    def discard_path
      helpers.discard_proposal_admin_modules_ai_assistant_message_path(message.customer_id, message)
    end

    # An update the assistant has proposed. Applied outranks a live offer,
    # which outranks a discarded one, which outranks a retired one — a
    # message should carry only one of these, but metadata is written by
    # several paths so the order is pinned.
    def proposal
      applied_proposal || pending_proposal || declined_proposal || superseded_proposal
    end

    # Applied is a fact about the past. Only a live pending offer can still
    # be applied, and only when this turn is the thread's active proposal.
    # A discarded or retired offer always renders read-only, even when this
    # component is mounted standalone with the default `true`.
    def proposal_state
      return :applied if applied_proposal
      return :pending if pending_proposal && @proposal_active
      return :declined if declined_proposal

      :superseded
    end

    # The sub-system build this reply belongs to, re-read so its state is
    # current. Only a build of this reply's own conversation counts.
    def subsystem_build
      return @subsystem_build if defined?(@subsystem_build)

      id = message.metadata_json.dig("subsystem_build", "id") unless user?
      @subsystem_build = id && AiAssistant::SubsystemBuild.unscoped.find_by(
        id: id, customer_id: message.customer_id, conversation_id: message.conversation_id
      )
    end

    def subsystem_build_badge = BUILD_BADGES.fetch(subsystem_build.status, :default)

    def cancel_build_path
      helpers.cancel_build_admin_modules_ai_assistant_message_path(message.customer_id, message)
    end

    def change_label(change)
      action = change["action"].to_s
      action = "created" unless %w[created updated reused].include?(action)
      kind = change["kind"].to_s
      kind = "entity" unless AiAssistant::Assistant::Artifact::KINDS.include?(kind)
      I18n.t(
        "ai_assistant.assistant.changes.#{action}",
        kind: I18n.t("ai_assistant.assistant.artifact.kinds.#{kind}"),
        name: change["name"]
      )
    end

    private

    def applied_proposal
      metadata_hash("applied_proposal")
    end

    def pending_proposal
      metadata_hash("pending_confirmation")
    end

    def declined_proposal
      metadata_hash("declined_proposal")
    end

    def superseded_proposal
      metadata_hash("superseded_proposal")
    end

    def questions_open?
      return false if questions.empty?
      return @questions_active unless @questions_active.nil?

      !later_message_exists?
    end

    def later_message_exists?
      message.conversation.messages.where("id > ?", message.id).exists?
    end

    def metadata_hash(key)
      value = message.metadata_json[key]
      value if value.is_a?(Hash)
    end
  end
end
