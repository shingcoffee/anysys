# frozen_string_literal: true

class AddDkimToEmailCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :email_credentials, :dkim_enabled, :boolean, null: false, default: false
    add_column :email_credentials, :dkim_domain, :string
    add_column :email_credentials, :dkim_selector, :string
    add_column :email_credentials, :dkim_private_key, :text
  end
end
