class MovePaymentCredentialsIntoConfig < ActiveRecord::Migration[8.1]
  def up
    add_column :payment_merchant_accounts, :credentials, :text

    # Backfill: collapse vendor-specific typed columns into a JSON blob keyed
    # by their original column name. Empty/null values are dropped so the
    # blob stays compact for fresh rows.
    execute <<~SQL.squish
      UPDATE payment_merchant_accounts
         SET credentials = (
           SELECT json_group_object(k, v) FROM (
             SELECT 'api_key_v3'              AS k, api_key_v3              AS v WHERE api_key_v3              IS NOT NULL AND api_key_v3              <> ''
             UNION ALL
             SELECT 'private_key_pem'         AS k, private_key_pem         AS v WHERE private_key_pem         IS NOT NULL AND private_key_pem         <> ''
             UNION ALL
             SELECT 'platform_public_key_pem' AS k, platform_public_key_pem AS v WHERE platform_public_key_pem IS NOT NULL AND platform_public_key_pem <> ''
             UNION ALL
             SELECT 'wechat_cert_serial'      AS k, wechat_cert_serial      AS v WHERE wechat_cert_serial      IS NOT NULL AND wechat_cert_serial      <> ''
           )
         )
    SQL

    remove_column :payment_merchant_accounts, :api_key_v3
    remove_column :payment_merchant_accounts, :private_key_pem
    remove_column :payment_merchant_accounts, :platform_public_key_pem
    remove_column :payment_merchant_accounts, :wechat_cert_serial
  end

  def down
    add_column :payment_merchant_accounts, :api_key_v3,              :text
    add_column :payment_merchant_accounts, :private_key_pem,         :text
    add_column :payment_merchant_accounts, :platform_public_key_pem, :text
    add_column :payment_merchant_accounts, :wechat_cert_serial,      :string

    execute <<~SQL.squish
      UPDATE payment_merchant_accounts
         SET api_key_v3              = json_extract(credentials, '$.api_key_v3'),
             private_key_pem         = json_extract(credentials, '$.private_key_pem'),
             platform_public_key_pem = json_extract(credentials, '$.platform_public_key_pem'),
             wechat_cert_serial      = json_extract(credentials, '$.wechat_cert_serial')
       WHERE credentials IS NOT NULL
    SQL

    remove_column :payment_merchant_accounts, :credentials
  end
end
