# frozen_string_literal: true

# Append-only audit log + single-use (replay) ledger for captcha verifications.
# Written on the public request path around tenant resolution, so customer_id is
# best-effort (nullable) and the table is deliberately NOT TenantScoped — mirrors
# the payment_webhook_events ledger rationale.
class CreateCaptchaVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table :captcha_verifications do |t|
      t.integer  :customer_id
      t.string   :provider, null: false
      t.string   :action
      t.string   :outcome, null: false
      t.decimal  :score, precision: 4, scale: 3
      t.string   :remoteip
      t.string   :hostname
      t.string   :token_digest, null: false
      t.datetime :created_at, null: false
    end

    # Single-use enforcement: a token may be *consumed* (succeed) at most once.
    # Partial-unique on success so repeated failed attempts (which may share a
    # digest, e.g. an empty token) never collide.
    add_index :captcha_verifications, :token_digest, unique: true,
              where: "outcome = 'success'",
              name: "index_captcha_verifications_single_use"
    add_index :captcha_verifications, [:customer_id, :created_at]
    add_index :captcha_verifications, [:provider, :created_at]
  end
end
