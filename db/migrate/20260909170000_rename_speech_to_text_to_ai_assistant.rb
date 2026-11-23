# frozen_string_literal: true

class RenameSpeechToTextToAiAssistant < ActiveRecord::Migration[8.1]
  # Conversations, messages, generations, and provider settings belong to the
  # AI Assistant module. Speech-to-text clips stay: they are transcription
  # artifacts only.
  TABLES = {
    speech_to_text_conversations: :ai_assistant_conversations,
    speech_to_text_messages: :ai_assistant_messages,
    speech_to_text_generations: :ai_assistant_generations,
    speech_to_text_provider_settings: :ai_assistant_provider_settings
  }.freeze

  INDEXES = {
    ai_assistant_conversations: {
      "index_speech_to_text_conversations_on_current_generation_id" =>
        "index_ai_assistant_conversations_on_current_generation_id",
      "idx_stt_conversations_on_customer_and_user" =>
        "idx_ai_assistant_conversations_on_customer_and_user",
      "index_speech_to_text_conversations_on_customer_id" =>
        "index_ai_assistant_conversations_on_customer_id"
    },
    ai_assistant_generations: {
      "index_speech_to_text_generations_on_conversation_id_and_status" =>
        "index_ai_assistant_generations_on_conversation_id_and_status",
      "index_speech_to_text_generations_on_conversation_id" =>
        "index_ai_assistant_generations_on_conversation_id",
      "index_speech_to_text_generations_on_customer_id" =>
        "index_ai_assistant_generations_on_customer_id",
      "index_speech_to_text_generations_on_token" =>
        "index_ai_assistant_generations_on_token",
      "index_speech_to_text_generations_on_user_message_id" =>
        "index_ai_assistant_generations_on_user_message_id"
    },
    ai_assistant_messages: {
      "index_speech_to_text_messages_on_conversation_id_and_id" =>
        "index_ai_assistant_messages_on_conversation_id_and_id",
      "index_speech_to_text_messages_on_customer_id" =>
        "index_ai_assistant_messages_on_customer_id"
    },
    ai_assistant_provider_settings: {
      "index_speech_to_text_provider_settings_on_provider" =>
        "index_ai_assistant_provider_settings_on_provider"
    }
  }.freeze

  PARTIAL_UNIQUE_INDEXES = [
    [ :generation_active, "index_stt_provider_settings_single_generation",
      "index_ai_assistant_provider_settings_single_generation" ],
    [ :transcribe_active, "index_stt_provider_settings_single_transcribe",
      "index_ai_assistant_provider_settings_single_transcribe" ]
  ].freeze

  def up
    TABLES.each { |from, to| rename_table from, to }
    rename_indexes(:up)
    rebuild_partial_unique_indexes(:up)
    update_feature_module_row!(from: "speech_to_text", to: "ai_assistant", name: "AI Assistant")
    update_active_storage_record_type!(from: "SpeechToText::Message", to: "AiAssistant::Message")
  end

  def down
    update_active_storage_record_type!(from: "AiAssistant::Message", to: "SpeechToText::Message")
    update_feature_module_row!(from: "ai_assistant", to: "speech_to_text", name: "Speech to text")
    rebuild_partial_unique_indexes(:down)
    rename_indexes(:down)
    TABLES.each { |from, to| rename_table to, from }
  end

  private

  def rename_indexes(direction)
    INDEXES.each do |table, pairs|
      pairs.each do |old_name, new_name|
        if direction == :up
          rename_index table, old_name, new_name
        else
          rename_index table, new_name, old_name
        end
      end
    end
  end

  # SQLite rename_index drops the partial WHERE clause on unique indexes,
  # turning "at most one true" into "generation_active must be unique" and
  # exploding on the many false rows. Rebuild instead of rename.
  def rebuild_partial_unique_indexes(direction)
    PARTIAL_UNIQUE_INDEXES.each do |column, old_name, new_name|
      from_name, to_name = direction == :up ? [ old_name, new_name ] : [ new_name, old_name ]
      remove_index :ai_assistant_provider_settings, name: from_name
      add_index :ai_assistant_provider_settings, column,
                unique: true, where: column.to_s, name: to_name
    end
  end

  def update_feature_module_row!(from:, to:, name:)
    from_id = module_id_for(from)
    to_id = module_id_for(to)

    if from_id && to_id && from_id != to_id
      merge_module_rows!(from_id: from_id, to_id: to_id, name: name)
    elsif from_id
      execute(<<~SQL.squish)
        UPDATE feature_modules
        SET key = #{connection.quote(to)}, name = #{connection.quote(name)}
        WHERE id = #{from_id}
      SQL
    elsif to_id
      execute(<<~SQL.squish)
        UPDATE feature_modules
        SET name = #{connection.quote(name)}
        WHERE id = #{to_id}
      SQL
    end
  end

  def module_id_for(key)
    row = select_one("SELECT id FROM feature_modules WHERE key = #{connection.quote(key)}")
    row && row["id"]
  end

  # Boot may have already inserted an ai_assistant row via Registration.register!
  # while the speech_to_text row still existed. Keep the destination row, fold
  # tenant assignments and logs onto it, then drop the old key.
  def merge_module_rows!(from_id:, to_id:, name:)
    keep_customer_ids = select_values(<<~SQL.squish)
      SELECT customer_id FROM customer_feature_modules
      WHERE feature_module_id = #{to_id}
    SQL
    if keep_customer_ids.any?
      listed = keep_customer_ids.map { |id| connection.quote(id) }.join(", ")
      execute(<<~SQL.squish)
        DELETE FROM customer_feature_modules
        WHERE feature_module_id = #{from_id}
          AND customer_id IN (#{listed})
      SQL
    end
    execute(<<~SQL.squish)
      UPDATE customer_feature_modules
      SET feature_module_id = #{to_id}
      WHERE feature_module_id = #{from_id}
    SQL
    execute(<<~SQL.squish)
      UPDATE feature_module_logs
      SET feature_module_id = #{to_id}
      WHERE feature_module_id = #{from_id}
    SQL
    execute("DELETE FROM feature_modules WHERE id = #{from_id}")
    execute(<<~SQL.squish)
      UPDATE feature_modules
      SET name = #{connection.quote(name)}
      WHERE id = #{to_id}
    SQL
  end

  def update_active_storage_record_type!(from:, to:)
    return unless table_exists?(:active_storage_attachments)

    execute(<<~SQL.squish)
      UPDATE active_storage_attachments
      SET record_type = #{connection.quote(to)}
      WHERE record_type = #{connection.quote(from)}
    SQL
  end
end
