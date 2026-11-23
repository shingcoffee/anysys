# frozen_string_literal: true

# Per-URL captcha access throttles. Platform form templates and shared-page
# templates have NULL customer_id (platform-wide policy). Tenant exact page
# URLs set customer_id.
class CreateCaptchaUrlThrottles < ActiveRecord::Migration[8.1]
  def change
    create_table :captcha_url_throttles do |t|
      t.string :match_kind, null: false
      t.string :url_pattern, null: false
      t.integer :limit_count
      t.integer :period_seconds
      t.boolean :every_hit, null: false, default: false
      t.bigint :customer_id
      t.string :surface_key
      t.bigint :page_id
      t.timestamps
    end

    add_index :captcha_url_throttles, %i[match_kind url_pattern], unique: true,
              name: "idx_captcha_url_throttles_kind_pattern"
    add_index :captcha_url_throttles, :customer_id
    add_index :captcha_url_throttles, :page_id
  end
end
