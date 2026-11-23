# frozen_string_literal: true

class CreateSpeechToTextClips < ActiveRecord::Migration[8.1]
  def change
    create_table :speech_to_text_clips do |t|
      t.bigint :customer_id, null: false
      t.bigint :user_id, null: false
      t.string :field_dom_id, null: false
      t.string :language
      t.string :status, null: false, default: "pending"
      t.string :error_code
      t.timestamps
    end

    add_index :speech_to_text_clips, :customer_id
    add_index :speech_to_text_clips, [ :customer_id, :created_at ]
  end
end
