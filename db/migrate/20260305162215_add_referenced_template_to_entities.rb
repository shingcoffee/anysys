class AddReferencedTemplateToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :referenced_template, :string
  end
end
