# frozen_string_literal: true

class LeanEmailModulePrune < ActiveRecord::Migration[8.1]
  def up
    # 1) Absorb block-list into suppressions before dropping user flags.
    say_with_time "migrate email_campaign_blocked users to suppressions" do
      execute <<~SQL.squish
        INSERT INTO email_suppressions (customer_id, email, reason, created_at)
        SELECT u.customer_id, LOWER(TRIM(u.email)), 'unsubscribe', CURRENT_TIMESTAMP
        FROM users u
        WHERE u.email_campaign_blocked = TRUE
          AND u.email IS NOT NULL
          AND TRIM(u.email) <> ''
          AND NOT EXISTS (
            SELECT 1 FROM email_suppressions s
            WHERE s.customer_id = u.customer_id
              AND s.email = LOWER(TRIM(u.email))
          )
      SQL
    end

    # 2) Drop FKs that reference pruned tables / columns.
    remove_foreign_key :email_campaigns, :email_segments if foreign_key_exists?(:email_campaigns, :email_segments)
    remove_foreign_key :email_campaigns, :email_streams if foreign_key_exists?(:email_campaigns, :email_streams)
    remove_foreign_key :email_lists, :email_segments if foreign_key_exists?(:email_lists, :email_segments)
    remove_foreign_key :email_messages, :email_streams if foreign_key_exists?(:email_messages, :email_streams)
    remove_foreign_key :email_templates, :email_streams if foreign_key_exists?(:email_templates, :email_streams)
    remove_foreign_key :email_user_preferences, :email_preference_topics if foreign_key_exists?(:email_user_preferences, :email_preference_topics)
    remove_foreign_key :email_preference_topics, :customers if foreign_key_exists?(:email_preference_topics, :customers)
    remove_foreign_key :email_segments, :customers if foreign_key_exists?(:email_segments, :customers)
    remove_foreign_key :email_signup_forms, :customers if foreign_key_exists?(:email_signup_forms, :customers)
    remove_foreign_key :email_streams, :customers if foreign_key_exists?(:email_streams, :customers)

    # 3) Drop dependent automation / preference tables first.
    drop_table :email_automation_enrollments, if_exists: true
    drop_table :email_automation_steps, if_exists: true
    drop_table :email_automations, if_exists: true
    drop_table :email_user_preferences, if_exists: true
    drop_table :email_preference_topics, if_exists: true
    drop_table :email_signup_forms, if_exists: true
    drop_table :email_segments, if_exists: true
    drop_table :email_streams, if_exists: true

    # 4) Strip pruned columns from kept tables.
    change_table :email_campaigns, bulk: true do |t|
      t.remove :ab_test_completed_at if column_exists?(:email_campaigns, :ab_test_completed_at)
      t.remove :ab_test_config if column_exists?(:email_campaigns, :ab_test_config)
      t.remove :ab_test_winner_variant if column_exists?(:email_campaigns, :ab_test_winner_variant)
      t.remove :email_segment_id if column_exists?(:email_campaigns, :email_segment_id)
      t.remove :email_stream_id if column_exists?(:email_campaigns, :email_stream_id)
    end

    change_table :email_lists, bulk: true do |t|
      t.remove :email_segment_id if column_exists?(:email_lists, :email_segment_id)
      t.remove :list_type if column_exists?(:email_lists, :list_type)
      t.remove :segment_rules if column_exists?(:email_lists, :segment_rules)
    end

    remove_column :email_messages, :email_stream_id if column_exists?(:email_messages, :email_stream_id)
    remove_column :email_templates, :builder_data if column_exists?(:email_templates, :builder_data)
    remove_column :email_templates, :email_stream_id if column_exists?(:email_templates, :email_stream_id)
    remove_column :email_credentials, :daily_limit if column_exists?(:email_credentials, :daily_limit)

    remove_index :users, name: "index_users_on_customer_id_and_email_campaign_blocked", if_exists: true
    remove_column :users, :email_campaign_blocked if column_exists?(:users, :email_campaign_blocked)
    remove_column :users, :email_campaign_blocked_at if column_exists?(:users, :email_campaign_blocked_at)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
