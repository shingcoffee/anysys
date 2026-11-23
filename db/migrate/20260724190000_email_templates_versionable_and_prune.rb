# frozen_string_literal: true

# Moves Emails::Template onto the shared content-addressed Versionable pattern
# (mirrors Page/PageVersion/PageConfigurationContent) and prunes the
# never-adopted key/template_type/category/variables columns. subject/
# body_html/body_text/editor_type stay real columns on email_templates for
# send-path performance; each save snapshots them into an immutable
# email_template_contents row referenced by an email_template_versions row.
#
# Backfill is pure raw SQL (no AR models) so it never depends on app code that
# may evolve after this migration is written, and never fires Versionable's
# after_save auto-commit or app-level validations while replaying history.
class EmailTemplatesVersionableAndPrune < ActiveRecord::Migration[8.1]
  def up
    create_table :email_template_contents do |t|
      t.integer  :customer_id, null: false
      t.string   :content_hash, null: false
      t.text     :payload, null: false
      t.datetime :created_at, null: false
    end
    add_index :email_template_contents, %i[customer_id content_hash], unique: true,
              name: "index_email_template_contents_on_customer_and_hash"
    add_index :email_template_contents, :customer_id

    create_table :email_template_versions_new do |t|
      t.integer  :email_template_id, null: false
      t.integer  :content_id, null: false
      t.integer  :based_on_version_id
      t.integer  :version_number, null: false
      t.string   :description
      t.integer  :customer_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    add_index :email_template_versions_new, %i[email_template_id version_number], unique: true,
              name: "index_email_template_versions_new_on_template_and_number"
    add_index :email_template_versions_new, :content_id
    add_index :email_template_versions_new, :customer_id

    say_with_time "Backfilling email_template_contents/email_template_versions from email_templates" do
      count = 0
      select_all("SELECT id, customer_id, subject, body_html, body_text, editor_type FROM email_templates").each do |row|
        payload = {
          "subject"     => row["subject"],
          "body_html"   => row["body_html"],
          "body_text"   => row["body_text"],
          "editor_type" => row["editor_type"],
          # No separate raw ActionText source exists in SQL; rich_text
          # templates fall back to body_html, matching the model's own
          # definition_snapshot fallback for a missing rich-text body.
          "body_raw"    => row["body_html"]
        }
        content_id = store_content!(customer_id: row["customer_id"], payload: payload)
        execute(<<~SQL.squish)
          INSERT INTO email_template_versions_new
            (email_template_id, content_id, version_number, description, customer_id, created_at, updated_at)
          VALUES
            (#{row['id'].to_i}, #{content_id.to_i}, 1, 'Initial version', #{quote(row['customer_id'])},
             CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
        count += 1
      end
      count
    end

    add_column :email_templates, :current_version_id, :integer
    execute(<<~SQL.squish)
      UPDATE email_templates SET current_version_id = (
        SELECT v.id FROM email_template_versions_new v
        WHERE v.email_template_id = email_templates.id
        ORDER BY v.version_number DESC LIMIT 1
      )
    SQL

    remove_index :email_templates, name: "index_email_templates_on_customer_id_and_key", if_exists: true
    remove_index :email_templates, name: "index_email_templates_on_customer_id_and_template_type", if_exists: true

    drop_table :email_template_versions
    rename_table :email_template_versions_new, :email_template_versions
    rename_index :email_template_versions, "index_email_template_versions_new_on_template_and_number",
                 "index_email_template_versions_on_template_id_and_version_number"

    change_table :email_templates, bulk: true do |t|
      t.remove :key, :template_type, :category, :variables
    end

    add_foreign_key :email_template_versions, :email_template_contents, column: :content_id
    add_foreign_key :email_template_versions, :email_templates
    add_foreign_key :email_template_versions, :email_template_versions, column: :based_on_version_id, on_delete: :nullify
    add_foreign_key :email_templates, :email_template_versions, column: :current_version_id, on_delete: :nullify
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Deterministic serialization matching ContentAddressable#canonical_json
  # (recursively key-sorted JSON) so post-migration application writes with an
  # identical payload dedup onto the same content row instead of creating a
  # near-duplicate.
  def canonical_json(payload)
    JSON.generate(payload.keys.sort.to_h { |k| [k, payload[k]] })
  end

  def store_content!(customer_id:, payload:)
    hash = Digest::SHA256.hexdigest(canonical_json(payload))
    existing = select_value(
      "SELECT id FROM email_template_contents WHERE customer_id = #{quote(customer_id)} AND content_hash = #{quote(hash)}"
    )
    return existing.to_i if existing

    execute(<<~SQL.squish)
      INSERT INTO email_template_contents (customer_id, content_hash, payload, created_at)
      VALUES (#{quote(customer_id)}, #{quote(hash)}, #{quote(canonical_json(payload))}, CURRENT_TIMESTAMP)
    SQL
    select_value(
      "SELECT id FROM email_template_contents WHERE customer_id = #{quote(customer_id)} AND content_hash = #{quote(hash)}"
    ).to_i
  end
end
