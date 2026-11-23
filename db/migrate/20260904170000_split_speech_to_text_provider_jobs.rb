# frozen_string_literal: true

# Split the single `enabled` flag into exclusive per-job assignees.
#
# This table has NO customer_id (platform-wide, same as today): vendor
# credentials are configured once by the platform owner and apply across
# tenants. Per-tenant enablement lives on FeatureModules::CustomerAssignment.
class SplitSpeechToTextProviderJobs < ActiveRecord::Migration[8.1]
  def up
    add_column :speech_to_text_provider_settings, :transcribe_active, :boolean, null: false, default: false
    add_column :speech_to_text_provider_settings, :generation_active, :boolean, null: false, default: false

    execute <<~SQL
      UPDATE speech_to_text_provider_settings
      SET transcribe_active = enabled, generation_active = enabled
    SQL

    remove_index :speech_to_text_provider_settings, name: "index_speech_to_text_provider_settings_single_active"
    remove_column :speech_to_text_provider_settings, :enabled

    add_index :speech_to_text_provider_settings, :transcribe_active,
              unique: true,
              where: "transcribe_active",
              name: "index_stt_provider_settings_single_transcribe"
    add_index :speech_to_text_provider_settings, :generation_active,
              unique: true,
              where: "generation_active",
              name: "index_stt_provider_settings_single_generation"
  end

  def down
    add_column :speech_to_text_provider_settings, :enabled, :boolean, null: false, default: false

    execute <<~SQL
      UPDATE speech_to_text_provider_settings
      SET enabled = CASE
        WHEN transcribe_active OR generation_active THEN 1
        ELSE 0
      END
    SQL

    remove_index :speech_to_text_provider_settings, name: "index_stt_provider_settings_single_transcribe"
    remove_index :speech_to_text_provider_settings, name: "index_stt_provider_settings_single_generation"
    remove_column :speech_to_text_provider_settings, :transcribe_active
    remove_column :speech_to_text_provider_settings, :generation_active

    add_index :speech_to_text_provider_settings, :enabled,
              unique: true,
              where: "enabled",
              name: "index_speech_to_text_provider_settings_single_active"
  end
end
