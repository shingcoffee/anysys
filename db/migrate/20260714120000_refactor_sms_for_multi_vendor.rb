# frozen_string_literal: true

# Rebuilds the SMS schema to be vendor-agnostic (Aliyun was hard-wired):
#   - credentials become vendor-keyed (provider + JSON config blob), unique per
#     (provider, mode), so a new vendor is a new row not a schema change
#   - templates map to a per-provider code (provider_template_codes JSON)
#   - messages carry their provider and gain the indexes delivery-receipt lookup
#     + reconciliation sweeps need
#   - a new sms_opt_outs ledger backs STOP/unsubscribe suppression
class RefactorSmsForMultiVendor < ActiveRecord::Migration[8.1]
  def up
    # --- credentials: vendor-keyed ---
    add_column :sms_credentials, :provider, :string
    add_column :sms_credentials, :config, :json, default: {}, null: false

    execute <<~SQL.squish
      UPDATE sms_credentials
         SET provider = 'aliyun',
             config = json_object('sign_name', sign_name, 'region', region)
    SQL

    change_column_null    :sms_credentials, :provider, false
    change_column_default :sms_credentials, :provider, from: nil, to: "aliyun"
    remove_index :sms_credentials, name: "index_sms_credentials_on_mode"
    add_index    :sms_credentials, %i[provider mode], unique: true,
                 name: "index_sms_credentials_on_provider_mode"
    remove_column :sms_credentials, :sign_name
    remove_column :sms_credentials, :region

    # --- templates: per-provider codes ---
    add_column :sms_templates, :provider_template_codes, :json, default: {}, null: false
    execute <<~SQL.squish
      UPDATE sms_templates
         SET provider_template_codes = json_object('aliyun', aliyun_template_code)
    SQL
    remove_column :sms_templates, :aliyun_template_code

    # --- messages: provider + delivery/reconcile indexes ---
    add_column :sms_messages, :provider, :string
    execute "UPDATE sms_messages SET provider = 'aliyun' WHERE provider IS NULL"
    add_index :sms_messages, :vendor_message_id
    add_index :sms_messages, :status

    # --- opt-out ledger ---
    # customer_id NULL = global opt-out (recipient replied STOP on the shared
    # vendor number → suppress across all tenants); customer_id set = a single
    # tenant's manual suppression. NOT TenantScoped (written from webhooks).
    create_table :sms_opt_outs do |t|
      t.integer  :customer_id
      t.string   :provider
      t.string   :phone_e164, null: false
      t.string   :reason
      t.datetime :created_at, null: false
    end
    add_index :sms_opt_outs, %i[customer_id phone_e164], unique: true
    add_index :sms_opt_outs, :phone_e164
  end

  def down
    drop_table :sms_opt_outs

    remove_index  :sms_messages, :status
    remove_index  :sms_messages, :vendor_message_id
    remove_column :sms_messages, :provider

    add_column :sms_templates, :aliyun_template_code, :string
    execute "UPDATE sms_templates SET aliyun_template_code = json_extract(provider_template_codes, '$.aliyun')"
    change_column_null :sms_templates, :aliyun_template_code, false
    remove_column :sms_templates, :provider_template_codes

    add_column :sms_credentials, :sign_name, :string
    add_column :sms_credentials, :region, :string, default: "cn-hangzhou", null: false
    execute <<~SQL.squish
      UPDATE sms_credentials
         SET sign_name = json_extract(config, '$.sign_name'),
             region    = COALESCE(json_extract(config, '$.region'), 'cn-hangzhou')
    SQL
    change_column_null :sms_credentials, :sign_name, false
    remove_index  :sms_credentials, name: "index_sms_credentials_on_provider_mode"
    add_index     :sms_credentials, :mode, unique: true, name: "index_sms_credentials_on_mode"
    remove_column :sms_credentials, :provider
    remove_column :sms_credentials, :config
  end
end
