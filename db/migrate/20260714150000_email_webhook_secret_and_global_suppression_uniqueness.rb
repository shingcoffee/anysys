# frozen_string_literal: true

# Security hardening from code review:
#   - The webhook signing secret must live in an ENCRYPTED column, not the
#     plaintext `config` JSON blob (consistent with password/dkim_private_key and
#     the SMS/captcha "secrets in encrypted columns" rule).
#   - The (customer_id, email/phone) unique indexes do NOT dedupe global rows
#     (customer_id IS NULL) on SQLite/standard SQL (NULLs compare distinct), so
#     add partial unique indexes to enforce single global-suppression rows.
class EmailWebhookSecretAndGlobalSuppressionUniqueness < ActiveRecord::Migration[8.1]
  def up
    add_column :email_credentials, :webhook_secret, :text

    # Migrate any existing plaintext webhook_secret out of the config blob. (New
    # app; if a value is present it is dev/test data — re-enter after this.)
    execute <<~SQL.squish
      UPDATE email_credentials
         SET config = json_remove(config, '$.webhook_secret')
       WHERE json_extract(config, '$.webhook_secret') IS NOT NULL
    SQL

    add_index :email_suppressions, :email, unique: true, where: "customer_id IS NULL",
              name: "index_email_suppressions_global_unique"
    add_index :sms_opt_outs, :phone_e164, unique: true, where: "customer_id IS NULL",
              name: "index_sms_opt_outs_global_unique"
  end

  def down
    remove_index :sms_opt_outs, name: "index_sms_opt_outs_global_unique"
    remove_index :email_suppressions, name: "index_email_suppressions_global_unique"
    remove_column :email_credentials, :webhook_secret
  end
end
