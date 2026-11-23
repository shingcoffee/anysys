# frozen_string_literal: true

class ReplacePageVisibilityWithAudiences < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :audience_admin, :boolean, null: false, default: true
    add_column :pages, :audience_member, :boolean, null: false, default: false
    add_column :pages, :audience_public, :boolean, null: false, default: false
    add_column :pages, :action_key, :string
    execute <<~SQL
      UPDATE pages
      SET audience_member = (visibility IN ('member', 'public')),
          audience_public = (visibility = 'public')
    SQL
    remove_column :pages, :visibility
    add_index :pages, %i[customer_id action_key]
  end

  def down
    add_column :pages, :visibility, :string, null: false, default: "admin"
    execute <<~SQL
      UPDATE pages
      SET visibility = CASE WHEN audience_public THEN 'public' WHEN audience_member THEN 'member' ELSE 'admin' END
    SQL
    remove_index :pages, %i[customer_id action_key]
    remove_column :pages, :action_key
    remove_column :pages, :audience_public
    remove_column :pages, :audience_member
    remove_column :pages, :audience_admin
  end
end
