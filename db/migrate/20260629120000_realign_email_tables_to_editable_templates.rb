# frozen_string_literal: true

# Reconciles the dev/schema drift left by the reverted fadd911 refactor: that
# (now-rolled-back) work slimmed email_templates to a registry pointer
# (mailer_action, no content) and dropped the message body columns. The restored
# code expects the customer-editable template content layer, so this brings both
# tables back in line with the committed schema (db/schema.rb version 000002).
#
# Idempotent column guards make this safe whether the table is in the slim state
# or already correct.
class RealignEmailTablesToEditableTemplates < ActiveRecord::Migration[8.1]
  def up
    change_table :email_templates, bulk: true do |t|
      t.remove :mailer_action if column_exists?(:email_templates, :mailer_action)
      t.string  :subject,     null: false, default: ""               unless column_exists?(:email_templates, :subject)
      t.text    :body_html,   null: false, default: ""               unless column_exists?(:email_templates, :body_html)
      t.text    :body_text                                           unless column_exists?(:email_templates, :body_text)
      t.json    :builder_data, null: false, default: {}              unless column_exists?(:email_templates, :builder_data)
      t.string  :editor_type, null: false, default: "code"           unless column_exists?(:email_templates, :editor_type)
      t.json    :variables,   null: false, default: []               unless column_exists?(:email_templates, :variables)
    end

    change_table :email_messages, bulk: true do |t|
      t.string :subject,   null: false, default: "" unless column_exists?(:email_messages, :subject)
      t.text   :body_html, null: false, default: "" unless column_exists?(:email_messages, :body_html)
      t.text   :body_text                           unless column_exists?(:email_messages, :body_text)
    end

    # Drop the placeholder column defaults so the schema matches the committed
    # null:false-without-default definitions (rows are truncated, so this is safe).
    change_column_default :email_templates, :subject,   from: "", to: nil
    change_column_default :email_templates, :body_html, from: "", to: nil
    change_column_default :email_messages,  :subject,   from: "", to: nil
    change_column_default :email_messages,  :body_html, from: "", to: nil
  end

  def down
    change_table :email_templates, bulk: true do |t|
      t.remove :subject, :body_html, :body_text, :builder_data, :editor_type, :variables
      t.string :mailer_action
    end
    change_table :email_messages, bulk: true do |t|
      t.remove :subject, :body_html, :body_text
    end
  end
end
