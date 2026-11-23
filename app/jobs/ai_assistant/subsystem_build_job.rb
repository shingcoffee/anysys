# frozen_string_literal: true

module AiAssistant
  class SubsystemBuildJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    # The build is started, and resumed, from inside an assistant turn. It
    # waits for that turn's reply so its own messages land after it.
    GENERATION_WAIT = 5.seconds

    def perform(build_id)
      build = AiAssistant::SubsystemBuild.unscoped.find_by(id: build_id)
      return if build.nil? || !build.running?
      return self.class.set(wait: GENERATION_WAIT).perform_later(build.id) if turn_in_progress?(build.conversation)

      Current.customer = build.customer
      locale = AiAssistant::Locale.for(user: build.user, customer: build.customer)
      I18n.with_locale(locale) { AiAssistant::Subsystems::Build.call(build: build) }
    ensure
      Current.reset
    end

    private

    def turn_in_progress?(conversation)
      generation = conversation.current_generation
      return false unless generation && AiAssistant::Generation::ACTIVE_STATUSES.include?(generation.status)

      !AiAssistant::Generation.stalled.exists?(generation.id)
    end
  end
end
