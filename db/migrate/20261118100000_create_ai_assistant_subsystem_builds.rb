# frozen_string_literal: true

class CreateAiAssistantSubsystemBuilds < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_assistant_subsystem_builds do |t|
      t.bigint :customer_id, null: false
      t.references :conversation, null: false,
                                  foreign_key: { to_table: :ai_assistant_conversations, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.string :status, null: false, default: "running"
      t.string :stage, null: false, default: "journeys"
      t.json :blueprint, null: false, default: {}
      t.json :questions, null: false, default: []
      t.json :answers, null: false, default: []
      t.json :results, null: false, default: {}
      t.timestamps
    end

    add_index :ai_assistant_subsystem_builds, :customer_id
    add_index :ai_assistant_subsystem_builds, :conversation_id,
              unique: true, where: "status IN ('running','waiting_for_answers')",
              name: "ai_assistant_one_active_subsystem_build"
  end
end
