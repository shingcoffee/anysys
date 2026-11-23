# frozen_string_literal: true

class AddAnnouncementInbox < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_announcements, :left_live_at, :datetime
    add_column :platform_announcements, :deleted_at, :datetime
    add_index :platform_announcements, :left_live_at
    add_index :platform_announcements, :deleted_at

    # Read receipt for the bell inbox. customer_id is the tenant CONTEXT of
    # the read (owner acting-as), not ownership of the announcement —
    # announcements remain a platform catalog with no customer_id.
    create_table :platform_announcement_reads do |t|
      t.references :platform_announcement, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :user_id, null: false
      t.integer :customer_id, null: false
      t.datetime :created_at, null: false
    end

    add_foreign_key :platform_announcement_reads, :users, on_delete: :cascade
    add_foreign_key :platform_announcement_reads, :customers, on_delete: :cascade

    add_index :platform_announcement_reads,
              [ :user_id, :customer_id, :platform_announcement_id ],
              unique: true,
              name: "idx_platform_announcement_reads_unique"
  end
end
