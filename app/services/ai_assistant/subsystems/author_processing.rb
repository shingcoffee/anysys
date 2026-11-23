# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Writes the processing one form page of a build needs: one flowchart
    # completion through the assistant's flowchart pass, with the build's
    # Screen added to its validation. Processing an earlier build wrote under
    # the same name is rewritten in place. A missing value comes back as
    # questions for the admin instead of a guess.
    class AuthorProcessing
      Result = Struct.new(:status, :flowchart, :questions, :needs_setup, :errors, keyword_init: true)
      Extraction = FlowchartDefinitions::Assistant::Extraction
      GEOMETRY = %w[x y width height].freeze

      def self.call(...) = new(...).call

      # +resumed+: an earlier run of this need was interrupted while writing;
      # +before_write+ is called right before the write and stops it when
      # it returns false (the build was cancelled).
      def initialize(build:, need:, page:, chat:, resumed: false, before_write: -> { true })
        @build = build
        @need = need
        @page = page
        @chat = chat
        @resumed = resumed
        @before_write = before_write
      end

      def call
        return failed(I18n.t("operations.violations.subsystem.processing_name_taken", name: name)) if name_taken?

        text = complete
        return unwritten(I18n.t("ai_assistant.assistant.flowchart_reply_failed")) if text.nil?

        extraction = Extraction.parse(text)
        return failed(I18n.t("ai_assistant.assistant.extraction_invalid")) unless extraction.valid?
        return asking(extraction.questions.presence || reply_question(extraction)) if extraction.intent == Extraction::Intent::CLARIFY
        return failed(extraction.reply.presence || I18n.t("ai_assistant.assistant.extraction_invalid")) unless extraction.persistable?

        apply(extraction)
      end

      private

      def name = @need["name"].to_s

      def earlier = defined?(@earlier) ? @earlier : (@earlier = EarlierProcessing.find(@build.customer_id, name) || (unrecorded if @resumed))

      # The name was free when the interrupted write began, so a flowchart
      # by it now is what that write left.
      def unrecorded = Flowchart.where(customer_id: @build.customer_id, name: name.squish).where.not(status: :deleted).first

      def name_taken?
        Flowchart.where(customer_id: [@build.customer_id, nil], name: name).where.not(status: :deleted).where.not(id: earlier&.id).exists?
      end

      def apply(extraction)
        document = extraction.as_json.merge("flowchart" => extraction.flowchart.merge("name" => name), "updates_confirmed" => false)
        normalized = FlowchartDefinitions::Normalizer.call(document["flowchart"])
        return asking([value_question]) if screen.unknown_values(normalized).any?
        return failed(nil) unless @before_write.call

        message = FlowchartDefinitions::Assistant::Processor.call(
          conversation: @build.conversation, customer: @build.customer, chat: @chat,
          text: document.to_json, screen: method(:screening), replaceable: earlier&.name
        )
        written = Array(message.created) + Array(message.updated)
        flowchart = Flowchart.find_by(customer_id: @build.customer_id, name: written.first) if written.any?
        return unwritten(message.body) unless flowchart

        Result.new(status: :created, flowchart: flowchart, questions: [], needs_setup: needs_setup(extraction, normalized), errors: [])
      end

      # A secret the first document tried to fill was repaired away, so it is
      # listed even when the model forgot to name it.
      def needs_setup(extraction, normalized)
        secrets = screen.secrets(normalized).map do |action, field|
          I18n.t("ai_assistant.subsystems.build.secret_setup",
                 step: I18n.t("flowchart_actions.#{action}.label", default: action),
                 field: I18n.t("flowchart_actions.#{action}.fields.#{field}.label", default: field))
        end
        (extraction.needs_setup + secrets).uniq
      end

      def complete
        result = @chat.call(messages)
        text = result.is_a?(Hash) ? result[:text].to_s.strip : ""
        text if result.is_a?(Hash) && result[:outcome] == :success && text.present?
      end

      def messages
        AiAssistant::Assistant::PromptBuilder.call(conversation: @build.conversation, mode: :flowchart) +
          [{ role: "user", content: instruction }]
      end

      def instruction
        values = Array(@need["values"]).map { |row| "- #{row["label"]}: #{row["value"]}" }
        {
          "{name}" => name,
          "{audience}" => @need["audience"].to_s,
          "{page}" => @page.name.to_s,
          "{entity}" => @need["entity"].to_s,
          "{purpose}" => @need["purpose"].to_s,
          "{values}" => values.any? ? values.join("\n") : "- (none)",
          "{answers}" => answers.presence || "- (none)",
          "{current}" => current
        }.reduce(AiAssistant::Assistant::Prompt::Document.read("subsystem_processing")) do |text, (token, value)|
          text.gsub(token) { value }
        end
      end

      def current
        return "" unless earlier

        flowchart = { "name" => earlier.name, "description" => earlier.description.to_s,
                      "elements" => Array(earlier.elements).map { |element| element.except(*GEOMETRY) },
                      "connections" => Array(earlier.connections) }
        text = AiAssistant::Assistant::Prompt::Document.read("subsystem_processing_rewrite")
        "\n#{text.gsub('{name}') { earlier.name }.gsub('{flowchart}') { flowchart.to_json }.strip}\n"
      end

      def answers = AnswerHistory.text(@build)

      def screen = @screen ||= Screen.for(@build.conversation, filled: filled_fields)

      # The page binds this processing only if it compiles against the page's
      # entity, so that check joins the repair loop instead of failing the
      # binding stage afterwards.
      def screening(normalized)
        draft = Flowchart.new(customer_id: @build.customer_id, name: name, configuration: normalized.configuration.to_json)
        screen.errors(normalized) + Flowcharts::Compatibility.problems(draft, @page.entity)
      end

      # Pages::AudienceGuard ties a member's record to their own person record,
      # and locked inputs carry records an earlier step picked.
      def filled_fields
        owner = People::Ownership.owner_reference(@page.entity)&.slug if @need["audience"].to_s == EntityAttributeAudience::MEMBER
        [owner, *@page.input_slugs].compact.map(&:to_s)
      end

      def reply_question(extraction)
        AiAssistant::Assistant::Questions.sanitize([{ "prompt" => extraction.reply, "type" => "text" }])
      end

      def value_question
        { "prompt" => I18n.t("ai_assistant.subsystems.build.value_question", name: name), "type" => "text" }
      end

      def asking(questions)
        questions = AiAssistant::Assistant::Questions.sanitize(questions)
        return failed(I18n.t("ai_assistant.assistant.extraction_invalid")) if questions.empty?

        Result.new(status: :questions, questions: questions, needs_setup: [], errors: [])
      end

      # The flowchart pass's own failure text talks about flowcharts, which
      # only the platform owner sees.
      def unwritten(detail)
        failed(FlowchartVisibility.allowed?(@build.user) ? detail : I18n.t("ai_assistant.subsystems.build.processing_unwritten"))
      end

      def failed(error)
        Result.new(status: :failed, questions: [], needs_setup: [], errors: [error.to_s].reject(&:blank?))
      end
    end
  end
end
