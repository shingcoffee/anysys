# frozen_string_literal: true

class CreateSpeechToTextProviderSettings < ActiveRecord::Migration[8.1]
  def change
    # Platform-wide vendor credentials (API key, model, organization). Intentionally
    # has no customer_id — the same justification as captcha_provider_settings:
    # the STT vendor is configured once by the platform owner and applies across
    # tenants. Per-tenant enablement lives on FeatureModules::CustomerAssignment.
    create_table :speech_to_text_provider_settings do |t|
      t.string :provider, null: false
      t.boolean :enabled, null: false, default: false
      t.text :api_key # AR encrypts at rest on the model
      t.text :config
      t.string :last_health_check_status
      t.string :last_health_check_message
      t.datetime :last_health_check_at
      t.timestamps
    end

    add_index :speech_to_text_provider_settings, :provider, unique: true
    add_index :speech_to_text_provider_settings, :enabled,
              unique: true,
              where: "enabled",
              name: "index_speech_to_text_provider_settings_single_active"
  end
end
