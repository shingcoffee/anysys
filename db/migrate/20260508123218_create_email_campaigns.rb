class CreateEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :email_campaigns do |t|
      t.integer :customer_id, null: false
      t.integer :email_template_id, null: false
      t.integer :email_list_id, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.string :recurrence_rule
      t.string :timezone, null: false, default: "UTC"
      t.json :stats, null: false, default: {}
      t.timestamps
    end

    add_index :email_campaigns, [:customer_id, :status]
    add_index :email_campaigns, [:status, :scheduled_at]
    add_index :email_campaigns, :email_template_id
    add_index :email_campaigns, :email_list_id
  end
end
