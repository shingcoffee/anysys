# frozen_string_literal: true

class CreateEmailAudienceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :email_tags do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6366f1"
      t.timestamps
    end
    add_index :email_tags, %i[customer_id name], unique: true

    create_table :email_taggings do |t|
      t.references :tag, null: false, foreign_key: { to_table: :email_tags }
      t.references :taggable, polymorphic: true, null: false, index: false
      t.timestamps
    end
    add_index :email_taggings, %i[taggable_type taggable_id]

    create_table :email_segments do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.json :rules, null: false, default: {}
      t.integer :match_count, null: false, default: 0
      t.datetime :match_count_refreshed_at
      t.timestamps
    end
    add_index :email_segments, %i[customer_id name], unique: true

    create_table :email_list_memberships do |t|
      t.references :email_list, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :email_list_memberships, %i[email_list_id user_id], unique: true

    create_table :email_signup_forms do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :key, null: false
      t.string :status, null: false, default: "active"
      t.json :settings, null: false, default: {}
      t.timestamps
    end
    add_index :email_signup_forms, %i[customer_id key], unique: true
  end
end
