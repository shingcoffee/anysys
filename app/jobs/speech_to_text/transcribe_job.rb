# frozen_string_literal: true

module SpeechToText
  # Solid Queue job: open the clip, bind Current.customer, call the vendor via
  # the Transcribe activity. Never runs on a Puma request thread.
  class TranscribeJob < ApplicationJob
    queue_as :default

    def perform(clip_id)
      clip = SpeechToText::Clip.find_by(id: clip_id)
      return if clip.nil?

      Current.customer = clip.customer
      SpeechToText::Activities::Transcribe.call(clip: clip)
    ensure
      Current.reset
    end
  end
end
