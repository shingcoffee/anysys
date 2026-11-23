class DropEmailTags < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :email_taggings, :email_tags if foreign_key_exists?(:email_taggings, :email_tags)
    drop_table :email_taggings, if_exists: true
    drop_table :email_tags, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
