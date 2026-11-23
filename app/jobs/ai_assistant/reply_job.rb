# frozen_string_literal: true

module AiAssistant
  class ReplyJob < ApplicationJob
    queue_as :default

    def perform(generation_id)
      generation = AiAssistant::Generation.find_by(id: generation_id)
      return if generation.nil?

      Current.customer = generation.customer
      locale = AiAssistant::Locale.for(
        user: generation.conversation.user,
        customer: generation.customer
      )
      I18n.with_locale(locale) do
        AiAssistant::Activities::Reply.call(generation: generation)
      end
    ensure
      Current.reset
    end
  end
end
