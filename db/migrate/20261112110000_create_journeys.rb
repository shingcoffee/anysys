# frozen_string_literal: true

class CreateJourneys < ActiveRecord::Migration[8.1]
  def change
    create_table :journeys do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :entity_domain, null: true, foreign_key: { on_delete: :nullify }
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.boolean :audience_admin, null: false, default: true
      t.boolean :audience_member, null: false, default: false
      t.boolean :audience_public, null: false, default: false
      t.text :definition
      t.timestamps null: false
    end
    add_index :journeys, %i[customer_id key], unique: true
    add_index :journeys, %i[customer_id status]

    add_reference :journey_runs, :journey, null: true, foreign_key: { on_delete: :cascade }
    add_column :journey_runs, :current_step, :string
  end
end
