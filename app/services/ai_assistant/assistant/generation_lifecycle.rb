# frozen_string_literal: true

module AiAssistant
  module Assistant
    class GenerationLifecycle
      class << self
        def start!(conversation:, user_message:)
          conversation.with_lock do
            supersede_current!(conversation)
            generation = conversation.generations.create!(
              customer_id: conversation.customer_id,
              user_message: user_message,
              token: SecureRandom.uuid
            )
            conversation.update!(current_generation: generation)
            generation
          end
        end

        def claim!(generation)
          conversation = generation.conversation
          conversation.with_lock do
            generation.reload
            return :stale unless conversation.current_generation_id == generation.id
            return :cancelled if generation.status == "cancelled"

            now = Time.current
            claimed = AiAssistant::Generation
                      .claimable
                      .where(id: generation.id)
                      .update_all(status: "running", started_at: now, updated_at: now) == 1
            generation.reload if claimed
            claimed ? :claimed : claim_failure(generation)
          end
        end

        def cancel!(conversation:)
          conversation.with_lock do
            generation = current_generation(conversation)
            return unless generation

            now = Time.current
            cancelled = AiAssistant::Generation
                        .where(id: generation.id, status: AiAssistant::Generation::ACTIVE_STATUSES)
                        .update_all(
                          status: "cancelled",
                          cancelled_at: now,
                          finished_at: now,
                          updated_at: now
                        ) == 1
            return unless cancelled

            generation.reload
          end
        end

        def finish!(generation, status:, failure_code: nil)
          terminal_status = status.to_s
          unless AiAssistant::Generation::TERMINAL_STATUSES.include?(terminal_status)
            raise ArgumentError, "status must be terminal"
          end

          conversation = generation.conversation
          pointer_cleared = conversation.with_lock do
            now = Time.current
            AiAssistant::Generation
              .where(id: generation.id, status: AiAssistant::Generation::ACTIVE_STATUSES)
              .update_all(
                status: terminal_status,
                failure_code: failure_code,
                finished_at: now,
                cancelled_at: cancelled_at(generation, terminal_status, now),
                updated_at: now
              )
            pointer_cleared = AiAssistant::Conversation
                              .where(id: conversation.id, current_generation_id: generation.id)
                              .update_all(current_generation_id: nil, updated_at: now) == 1
            pointer_cleared
          end
          generation.reload
          pointer_cleared
        end

        private

        def supersede_current!(conversation)
          generation = current_generation(conversation)
          return unless generation

          now = Time.current
          AiAssistant::Generation
            .where(id: generation.id, status: AiAssistant::Generation::ACTIVE_STATUSES)
            .update_all(status: "superseded", finished_at: now, updated_at: now)
        end

        def current_generation(conversation)
          return unless conversation.current_generation_id

          conversation.generations.find_by(id: conversation.current_generation_id)
        end

        def claim_failure(generation)
          generation.reload.status == "cancelled" ? :cancelled : :stale
        end

        def cancelled_at(generation, status, now)
          return generation.cancelled_at unless status == "cancelled"

          generation.cancelled_at || now
        end
      end
    end
  end
end
