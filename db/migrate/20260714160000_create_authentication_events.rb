# frozen_string_literal: true

# Auth audit-log ledger (OWASP ASVS): a durable trail of security-relevant auth
# events — logins (success/failure), lockouts, MFA changes/verifications,
# password resets, role grants/revocations, throttling. Written from a
# Notifications subscriber so controllers stay decoupled. NOT TenantScoped:
# pre-auth events (failed login) may not resolve a tenant/user, so customer_id /
# user_id are best-effort (nullable).
class CreateAuthenticationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :authentication_events do |t|
      t.integer  :customer_id
      t.integer  :user_id
      t.string   :event, null: false
      t.string   :ip
      t.string   :user_agent
      t.json     :metadata, default: {}, null: false
      t.datetime :created_at, null: false
    end

    add_index :authentication_events, %i[customer_id created_at]
    add_index :authentication_events, %i[user_id created_at]
    add_index :authentication_events, %i[event created_at]
  end
end
