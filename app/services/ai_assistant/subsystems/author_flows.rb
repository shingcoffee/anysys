# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The journey stage of a build: one completion that analyses the brief and
    # designs the business flows (schemas/flows.json) in business terms, before
    # any entity exists. The reply is checked against the schema and
    # FlowCheck, and the problems go back to the model for repair. The model
    # may ask the admin once; asked again, it is told to decide.
    class AuthorFlows
      Result = Struct.new(:status, :flows, :questions, :errors, keyword_init: true)
      ATTEMPTS = 3
      ENTITY_LIMIT = 40
      NO_MORE_QUESTIONS = "The admin can't be asked again. Decide from the brief and the answers, and list what you assumed under not_covered."

      def self.call(...) = new(...).call

      # +feedback+: the platform owner's change request for earlier flows.
      def initialize(build:, chat:, may_ask: true, feedback: nil, previous: nil)
        @build = build
        @chat = chat
        @may_ask = may_ask
        @feedback = feedback
        @previous = previous
      end

      def call
        messages = [{ role: "system", content: system_prompt }, { role: "user", content: instruction }]
        problems = []
        ATTEMPTS.times do
          text = complete(messages)
          return failed(["The model did not reply."]) if text.nil?

          outcome = review(AiAssistant::Assistant::JsonDocument.parse(text))
          return outcome if outcome.is_a?(Result)

          problems = outcome
          messages += [{ role: "assistant", content: text }, { role: "user", content: repair(problems) }]
        end
        failed(problems)
      end

      private

      def brief = @build.brief

      # A Result when the reply can be used, otherwise its problems.
      def review(reply)
        return ["Reply with one JSON object only."] unless reply.is_a?(Hash)
        return ask(reply["questions"]) if reply.key?("questions") && !reply.key?("journeys")

        problems = Flows.schema_errors(reply)
        problems = FlowCheck.call(flows: Flows.new(reply), brief: brief) if problems.empty?
        problems.empty? ? Result.new(status: :flows, flows: reply, questions: [], errors: []) : problems
      end

      def ask(raw)
        questions = AiAssistant::Assistant::Questions.sanitize(raw)
        return [NO_MORE_QUESTIONS] unless @may_ask && questions.any?

        Result.new(status: :questions, questions: questions, errors: [])
      end

      def complete(messages)
        result = @chat.call(messages)
        text = result.is_a?(Hash) ? result[:text].to_s.strip : ""
        text if result.is_a?(Hash) && result[:outcome] == :success && text.present?
      end

      def system_prompt
        AiAssistant::Assistant::Prompt::Document.read("subsystem_flows")
                                               .gsub("{schema}") { JSON.pretty_generate(Flows.schema) }
      end

      def instruction
        [
          "## Brief\n```json\n#{JSON.pretty_generate(brief.to_h)}\n```",
          section("Answers the admin gave", AnswerHistory.text(@build)),
          section("Entities this workspace already has", existing_entities.join(", ")),
          section("Your earlier flows", @previous && "```json\n#{JSON.pretty_generate(@previous)}\n```"),
          section("Change these flows as the platform owner asks", @feedback),
          @may_ask ? nil : NO_MORE_QUESTIONS
        ].compact.join("\n\n")
      end

      def section(title, body) = body.to_s.strip.present? ? "## #{title}\n#{body.to_s.strip}" : nil

      def existing_entities
        Entity.where(customer_id: [@build.customer_id, nil]).order(:name).limit(ENTITY_LIMIT).map { |entity| entity.display_label.presence || entity.name }
      end

      def repair(problems)
        "Fix these problems and reply with the whole corrected JSON object only:\n#{problems.map { |problem| "- #{problem}" }.join("\n")}"
      end

      def failed(problems)
        Rails.logger.warn("#{Build::LOG_TAG} build=#{@build.id} flows unusable: #{problems.join(' | ')}")
        Result.new(status: :failed, questions: [], errors: problems)
      end
    end
  end
end
