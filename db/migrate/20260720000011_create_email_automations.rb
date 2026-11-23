# frozen_string_literal: true

class CreateEmailAutomations < ActiveRecord::Migration[8.1]
  def change
    create_table :email_automations do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.string :trigger_kind, null: false
      t.json :trigger_config, null: false, default: {}
      t.timestamps
    end

    create_table :email_automation_steps do |t|
      t.references :email_automation, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :step_type, null: false
      t.json :config, null: false, default: {}
      t.references :email_template, foreign_key: true
      t.timestamps
    end
    add_index :email_automation_steps, %i[email_automation_id position], unique: true

    create_table :email_automation_enrollments do |t|
      t.references :email_automation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.integer :current_step_position, null: false, default: 0
      t.datetime :next_step_at
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :email_automation_enrollments, %i[email_automation_id user_id], unique: true
  end
end
