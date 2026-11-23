# frozen_string_literal: true

# Records at enqueue time where a finished transcript belongs — the field it was
# dictated into, or the AI assistant thread. Previously the transcribe job
# always forwarded to the assistant, so DictateFieldComponent mounted on any
# other field silently posted the user's dictation into their assistant
# conversation instead of filling the field.
class AddDestinationToSpeechToTextClips < ActiveRecord::Migration[8.1]
  def change
    add_column :speech_to_text_clips, :destination, :string, null: false, default: "field"
  end
end
