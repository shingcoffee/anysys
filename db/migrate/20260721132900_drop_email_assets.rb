class DropEmailAssets < ActiveRecord::Migration[8.1]
  def change
    drop_table :email_assets do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "image"
      t.timestamps
    end
  end
end
