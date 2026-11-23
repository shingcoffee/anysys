# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Routes a message sent while the conversation has an active build. A
    # build waiting for answers takes the message as its answers and resumes;
    # a running one gets a short notice instead of a model turn. A build whose
    # worker is gone is failed, and the message goes to the assistant as usual.
    class Answer
      def self.consume(...) = new(...).call

      def initialize(conversation:, user_message:)
        @conversation = conversation
        @user_message = user_message
      end

      def call
        build = AiAssistant::SubsystemBuild.unscoped.active.where(conversation_id: @conversation.id).order(:id).last
        return unless build

        build.with_lock do
          if build.waiting_for_answers?
            resume(build)
          elsif build.stalled?
            build.update!(status: "failed", results: build.results_json.merge("error" => "stalled"))
            nil
          elsif build.running?
            turn(build, I18n.t("ai_assistant.subsystems.answers.running", name: build.name), "running")
          end
        end
      end

      private

      def resume(build)
        build.update!(status: "running", questions: [],
                      answers: Array(build.answers) + [{ "message_id" => @user_message.id, "questions" => build.questions }])
        AiAssistant::SubsystemBuildJob.perform_later(build.id)
        turn(build, I18n.t("ai_assistant.subsystems.answers.received", name: build.name), "resumed")
      end

      def turn(build, body, action)
        AiAssistant::Assistant::TurnProcessor::Result.new(
          body: body, status: "complete", effects: [{ kind: "subsystem_build", action: action, record: build }]
        )
      end
    end
  end
end
