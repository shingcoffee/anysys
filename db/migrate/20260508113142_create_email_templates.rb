class CreateEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :email_templates do |t|
      t.integer :customer_id, null: false
      t.string :key, null: false
      t.string :name, null: false
      t.string :subject, null: false
      t.text :body_html, null: false
      t.text :body_text
      t.string :template_type, null: false, default: "transactional"
      t.string :editor_type, null: false, default: "code"
      t.json :builder_data, null: false, default: {}
      t.json :variables, null: false, default: []
      t.string :status, null: false, default: "draft"
      t.timestamps
    end

    add_index :email_templates, [:customer_id, :key], unique: true
    add_index :email_templates, [:customer_id, :template_type]
    add_index :email_templates, :customer_id
  end
end
