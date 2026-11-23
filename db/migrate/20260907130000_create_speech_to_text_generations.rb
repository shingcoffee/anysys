# frozen_string_literal: true

class CreateSpeechToTextGenerations < ActiveRecord::Migration[8.1]
  def change
    create_table :speech_to_text_generations do |t|
      t.bigint :customer_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :user_message_id, null: false
      t.string :token, null: false
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :cancelled_at
      t.string :failure_code
      t.timestamps
    end

    add_index :speech_to_text_generations, :customer_id
    add_index :speech_to_text_generations, :conversation_id
    add_index :speech_to_text_generations, :user_message_id
    add_index :speech_to_text_generations, :token, unique: true
    add_index :speech_to_text_generations, [ :conversation_id, :status ]

    add_reference :speech_to_text_conversations, :current_generation,
                  type: :bigint, index: true
    remove_column :speech_to_text_conversations, :generation_token, :string
    remove_column :speech_to_text_conversations, :cancel_token, :string
  end
end
