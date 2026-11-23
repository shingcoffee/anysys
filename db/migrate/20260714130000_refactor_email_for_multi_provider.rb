# frozen_string_literal: true

# Makes the Email module provider-agnostic (SMTP was hard-wired):
#   - credentials gain a `provider` + JSON `config` blob (API vendors like
#     Postmark store their config there; SMTP keeps its typed columns as the
#     standard protocol field set). Unique per (provider, mode).
#   - messages carry their provider + provider_message_id (webhook DLR lookup).
#   - a new email_suppressions ledger backs bounce/complaint suppression.
class RefactorEmailForMultiProvider < ActiveRecord::Migration[8.1]
  def up
    add_column :email_credentials, :provider, :string
    add_column :email_credentials, :config, :json, default: {}, null: false
    execute "UPDATE email_credentials SET provider = 'smtp'"
    change_column_null    :email_credentials, :provider, false
    change_column_default :email_credentials, :provider, from: nil, to: "smtp"

    # Relax SMTP-specific NOT NULLs so API providers (no host/username) fit.
    change_column_null :email_credentials, :host, true
    change_column_null :email_credentials, :username, true

    remove_index :email_credentials, name: "index_email_credentials_on_mode"
    add_index    :email_credentials, %i[provider mode], unique: true,
                 name: "index_email_credentials_on_provider_mode"

    add_column :email_messages, :provider, :string
    add_column :email_messages, :provider_message_id, :string
    execute "UPDATE email_messages SET provider = 'smtp' WHERE provider IS NULL"
    add_index :email_messages, :provider_message_id

    # Suppression ledger. customer_id NULL = global (all tenants on the shared
    # sending domain); set = one tenant's suppression. NOT TenantScoped.
    create_table :email_suppressions do |t|
      t.integer  :customer_id
      t.string   :email, null: false
      t.string   :reason
      t.string   :provider
      t.datetime :created_at, null: false
    end
    add_index :email_suppressions, %i[customer_id email], unique: true
    add_index :email_suppressions, :email
  end

  def down
    drop_table :email_suppressions

    remove_index  :email_messages, :provider_message_id
    remove_column :email_messages, :provider_message_id
    remove_column :email_messages, :provider

    remove_index :email_credentials, name: "index_email_credentials_on_provider_mode"
    add_index    :email_credentials, :mode, unique: true, name: "index_email_credentials_on_mode"
    change_column_null :email_credentials, :username, false
    change_column_null :email_credentials, :host, false
    remove_column :email_credentials, :provider
    remove_column :email_credentials, :config
  end
end
