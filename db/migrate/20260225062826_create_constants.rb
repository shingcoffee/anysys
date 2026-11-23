class CreateConstants < ActiveRecord::Migration[8.1]
  def change
    create_table :constants do |t|
      t.string :name, null: false
      t.string :constant_type, null: false
      t.json :options, default: []

      t.timestamps
    end

    add_index :constants, :name
    add_index :constants, :constant_type
  end
end
