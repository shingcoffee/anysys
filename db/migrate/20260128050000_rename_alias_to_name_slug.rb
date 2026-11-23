class RenameAliasToNameSlug < ActiveRecord::Migration[8.1]
  def change
    rename_column :resources, :alias, :name_slug
  end
end
