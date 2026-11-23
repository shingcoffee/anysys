class CreateCustomElements < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_elements do |t|
      t.string :name, null: false
      t.string :element_type, null: false, default: 'custom'
      t.string :icon, default: 'custom'
      t.string :color, default: '#6366f1'
      t.text :description
      t.text :default_properties
      t.text :property_schema

      t.timestamps
    end

    add_index :custom_elements, :name
    add_index :custom_elements, :element_type
    add_index :custom_elements, :created_at
  end
end
