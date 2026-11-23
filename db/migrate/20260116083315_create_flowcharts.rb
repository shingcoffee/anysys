class CreateFlowcharts < ActiveRecord::Migration[8.1]
  def change
    create_table :flowcharts do |t|
      t.string :name, null: false
      t.text :description
      t.text :configuration, null: false

      t.timestamps
    end

    add_index :flowcharts, :name
    add_index :flowcharts, :created_at
  end
end
