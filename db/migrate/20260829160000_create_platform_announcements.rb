# frozen_string_literal: true

class CreatePlatformAnnouncements < ActiveRecord::Migration[8.1]
  def change
    # Platform catalog (no customer_id): same justification as billing_plans —
    # owned by the platform, not a tenant. CUD only via
    # /81721200/admin/maintenance/platform/announcements.
    create_table :platform_announcements do |t|
      t.string :title, null: false
      t.text :body_en, null: false
      t.text :body_zh, null: false
      t.string :severity, null: false, default: "info"
      t.string :link_url
      t.string :status, null: false, default: "draft"
      t.string :audience, null: false, default: "all"
      t.json :target_rules, null: false, default: {}
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end

    # Covers the hot banner lookup: published rows ordered newest-first, with
    # the schedule window narrowed in the same index.
    add_index :platform_announcements,
              [ :status, :starts_at, :ends_at ],
              name: "idx_platform_announcements_live"

    # Per-user dismissal. Session storage would resurrect the banner in every
    # new session/browser, so the acknowledgement is persisted instead.
    # customer_id records the tenant context the admin dismissed it in — the
    # platform owner acting as several tenants dismisses per tenant.
    create_table :platform_announcement_dismissals do |t|
      t.references :platform_announcement, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :user_id, null: false
      t.integer :customer_id, null: false
      t.datetime :created_at, null: false
    end

    add_foreign_key :platform_announcement_dismissals, :users, on_delete: :cascade
    add_foreign_key :platform_announcement_dismissals, :customers, on_delete: :cascade

    add_index :platform_announcement_dismissals,
              [ :user_id, :customer_id, :platform_announcement_id ],
              unique: true,
              name: "idx_platform_announcement_dismissals_unique"
  end
end
