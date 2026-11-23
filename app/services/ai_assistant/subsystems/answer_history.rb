# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The admin's latest answers to a build's questions, as prompt text. The
    # question prompts live only in the build's messages' metadata, so the
    # reply alone would not say what it answers.
    module AnswerHistory
      ROUNDS = 3

      def self.text(build, rounds: ROUNDS)
        replies(build, rounds).map do |round, reply|
          prompts = Array(round["questions"]).grep(Hash).map { |question| "- #{question["prompt"]}" }
          [*prompts, "Reply: #{reply.body.to_s.strip}"].join("\n")
        end.join("\n\n")
      end

      # [[round, message]] for the last +rounds+ answered rounds, oldest first.
      def self.replies(build, rounds = ROUNDS)
        list = Array(build.answers).last(rounds).grep(Hash)
        found = build.conversation.messages.where(role: "user", id: list.map { |round| round["message_id"] }).index_by(&:id)
        list.filter_map { |round| (reply = found[round["message_id"]]) && [round, reply] }
      end
    end
  end
end
