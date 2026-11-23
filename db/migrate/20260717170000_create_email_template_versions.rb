class CreateEmailTemplateVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :email_template_versions do |t|
      t.integer :email_template_id, null: false
      t.json :snapshot, null: false
      t.integer :created_by_id

      t.timestamps
    end

    add_index :email_template_versions, [:email_template_id, :created_at]
  end
end
