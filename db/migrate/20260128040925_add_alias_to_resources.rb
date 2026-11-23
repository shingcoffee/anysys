class AddAliasToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :alias, :string
  end
end
