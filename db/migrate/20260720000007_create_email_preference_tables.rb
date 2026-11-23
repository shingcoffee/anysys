# frozen_string_literal: true

class CreateEmailPreferenceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :email_preference_topics do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :default_subscribed, null: false, default: true
      t.boolean :required, null: false, default: false
      t.timestamps
    end
    add_index :email_preference_topics, %i[customer_id key], unique: true

    create_table :email_user_preferences do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.references :email_preference_topic, null: false, foreign_key: true
      t.boolean :subscribed, null: false, default: true
      t.timestamps
    end
    add_index :email_user_preferences, %i[user_id email_preference_topic_id], unique: true
  end
end
