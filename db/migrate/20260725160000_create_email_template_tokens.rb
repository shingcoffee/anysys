# frozen_string_literal: true

class CreateEmailTemplateTokens < ActiveRecord::Migration[8.1]
  PLATFORM_SEEDS = [
    { source_key: "unsubscribe_url", label_key: "unsubscribe_url" }
  ].freeze

  def up
    wipe_email_templates!

    create_table :email_template_tokens do |t|
      t.string  :uuid,           null: false
      t.integer :customer_id
      t.string  :label,          null: false
      t.string  :source_type,    null: false
      t.string  :source_key
      t.integer :entity_id
      t.string  :attribute_slug
      t.timestamps
    end

    add_index :email_template_tokens, :uuid, unique: true
    add_index :email_template_tokens, :customer_id
    add_index :email_template_tokens,
              %i[customer_id entity_id attribute_slug],
              unique: true,
              where: "customer_id IS NOT NULL AND source_type = 'entity_attribute'",
              name: "idx_email_template_tokens_customer_entity_attr"
    add_index :email_template_tokens,
              :source_key,
              unique: true,
              where: "customer_id IS NULL AND source_type = 'platform_field'",
              name: "idx_email_template_tokens_platform_source_key"

    seed_platform_tokens!
  end

  def down
    drop_table :email_template_tokens
  end

  private

  def wipe_email_templates!
    # Fresh cutover — no legacy {{name}} tokens. Clear dependents first so
    # restrict_with_exception / FKs do not block the wipe.
    execute "UPDATE email_send_activities SET email_template_id = NULL"
    execute "UPDATE email_messages SET email_template_id = NULL"
    execute "UPDATE email_templates SET current_version_id = NULL"
    execute "DELETE FROM email_template_versions"
    execute "DELETE FROM email_template_contents"
    execute "DELETE FROM action_text_rich_texts WHERE record_type = 'Emails::Template'"
    execute "DELETE FROM email_templates"
  end

  def seed_platform_tokens!
    now = Time.current
    PLATFORM_SEEDS.each do |seed|
      execute ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          INSERT INTO email_template_tokens
            (uuid, customer_id, label, source_type, source_key, entity_id, attribute_slug, created_at, updated_at)
          VALUES (?, NULL, ?, 'platform_field', ?, NULL, NULL, ?, ?)
        SQL
        SecureRandom.uuid, seed[:label_key], seed[:source_key], now, now
      ])
    end
  end
end
