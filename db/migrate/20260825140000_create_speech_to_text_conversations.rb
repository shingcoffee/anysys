# frozen_string_literal: true

class CreateSpeechToTextConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :speech_to_text_conversations do |t|
      t.bigint :customer_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end

    add_index :speech_to_text_conversations, :customer_id
    add_index :speech_to_text_conversations, [ :customer_id, :user_id ], unique: true,
              name: "idx_stt_conversations_on_customer_and_user"
  end
end
