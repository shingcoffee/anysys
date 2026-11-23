class ChangeReferencedTemplateToTextInEntities < ActiveRecord::Migration[8.1]
  def up
    change_column :entities, :referenced_template, :text
  end

  def down
    change_column :entities, :referenced_template, :string
  end
end
