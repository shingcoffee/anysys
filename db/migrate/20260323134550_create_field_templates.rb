class CreateFieldTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :field_templates do |t|
      t.bigint :customer_id, null: false
      t.string :name, null: false
      t.string :category
      t.text :description
      t.json :configuration, null: false, default: {}
      t.boolean :built_in, default: false, null: false
      t.timestamps
    end

    add_index :field_templates, :customer_id
    add_index :field_templates, [:customer_id, :category]
    add_index :field_templates, [:customer_id, :built_in]
  end
end
