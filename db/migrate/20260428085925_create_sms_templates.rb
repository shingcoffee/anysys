class CreateSmsTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_templates do |t|
      t.string :key,                  null: false
      t.string :aliyun_template_code, null: false
      t.string :description
      t.json   :variables,            null: false, default: []
      t.string :status,               null: false, default: "active"
      t.timestamps
    end
    add_index :sms_templates, :key, unique: true
  end
end
