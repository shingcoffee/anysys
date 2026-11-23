# frozen_string_literal: true

module SpeechToText
  # Recurring cleanup (config/recurring.yml: speech_to_text_prune_clips).
  # Terminalizes abandoned work after five minutes, purges leftover audio,
  # and retains terminal rows for 15 minutes so polling clients see failures.
  class PruneClipsJob < ApplicationJob
    queue_as :default

    MAX_AGE = 15.minutes
    RECOVERY_AGE = 5.minutes

    def perform(now: Time.current)
      stale = SpeechToText::Clip.where(status: %w[pending processing], updated_at: ...now - RECOVERY_AGE)
      stale.find_each do |clip|
        changed = stale.where(id: clip.id).update_all(status: "failed", error_code: "generic_error", updated_at: now) == 1
        SpeechToText::BroadcastResult.call(clip: clip.reload) if changed
      rescue StandardError => e
        Rails.logger.error("[speech_to_text.prune] recovery failed clip=#{clip.id}: #{e.class}: #{e.message}")
      end
      SpeechToText::Clip.where(status: SpeechToText::Clip::TERMINAL_STATUSES).find_each do |clip|
        # ActiveStorage purge touches the owning clip's updated_at. Decide
        # retention from the recorded terminal age before detaching audio.
        finished_at = clip.updated_at
        clip.audio.purge if clip.audio.attached?
        clip.destroy! if finished_at < now - MAX_AGE
      rescue StandardError => e
        Rails.logger.error("[speech_to_text.prune] clip=#{clip.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
