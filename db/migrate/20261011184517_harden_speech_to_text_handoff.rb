# frozen_string_literal: true

class HardenSpeechToTextHandoff < ActiveRecord::Migration[8.1]
  def change
    add_reference :speech_to_text_clips, :conversation,
                  foreign_key: { to_table: :ai_assistant_conversations, on_delete: :nullify }
    add_column :speech_to_text_clips, :started_at, :datetime
    add_column :speech_to_text_clips, :transcript, :text
    add_index :speech_to_text_clips, [:status, :updated_at]
  end
end
