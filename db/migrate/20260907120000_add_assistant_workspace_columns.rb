# frozen_string_literal: true

class AddAssistantWorkspaceColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :speech_to_text_conversations, :artifact_kind, :string
    add_column :speech_to_text_conversations, :artifact_id, :bigint
    add_column :speech_to_text_conversations, :generation_token, :string
    add_column :speech_to_text_conversations, :cancel_token, :string
    add_column :speech_to_text_messages, :metadata, :json, default: {}, null: false
  end
end
