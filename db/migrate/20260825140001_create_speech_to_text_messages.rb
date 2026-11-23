# frozen_string_literal: true

class CreateSpeechToTextMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :speech_to_text_messages do |t|
      t.bigint :customer_id, null: false
      t.bigint :conversation_id, null: false
      t.string :role, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "complete"
      t.timestamps
    end

    add_index :speech_to_text_messages, :customer_id
    add_index :speech_to_text_messages, [ :conversation_id, :id ]
  end
end
