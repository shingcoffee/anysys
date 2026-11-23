class AddModelToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :model, :text
  end
end
