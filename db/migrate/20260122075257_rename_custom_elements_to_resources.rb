class RenameCustomElementsToResources < ActiveRecord::Migration[8.1]
  def change
    rename_table :custom_elements, :resources
  end
end
