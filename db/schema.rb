# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_23_120000) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["customer_id"], name: "index_active_storage_blobs_on_customer_id"
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_assistant_conversations", force: :cascade do |t|
    t.datetime "archived_at"
    t.bigint "artifact_id"
    t.string "artifact_kind"
    t.datetime "created_at", null: false
    t.bigint "current_generation_id"
    t.bigint "customer_id", null: false
    t.datetime "last_active_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["current_generation_id"], name: "index_ai_assistant_conversations_on_current_generation_id"
    t.index ["customer_id", "user_id", "archived_at", "last_active_at"], name: "idx_ai_assistant_conversations_on_owner_and_activity"
    t.index ["customer_id"], name: "index_ai_assistant_conversations_on_customer_id"
  end

  create_table "ai_assistant_generations", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "failure_code"
    t.datetime "finished_at"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_message_id", null: false
    t.index ["conversation_id", "status"], name: "index_ai_assistant_generations_on_conversation_id_and_status"
    t.index ["conversation_id"], name: "index_ai_assistant_generations_on_conversation_id"
    t.index ["customer_id"], name: "index_ai_assistant_generations_on_customer_id"
    t.index ["token"], name: "index_ai_assistant_generations_on_token", unique: true
    t.index ["user_message_id"], name: "index_ai_assistant_generations_on_user_message_id"
  end

  create_table "ai_assistant_messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.json "metadata", default: {}, null: false
    t.string "role", null: false
    t.string "status", default: "complete", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "id"], name: "index_ai_assistant_messages_on_conversation_id_and_id"
    t.index ["customer_id"], name: "index_ai_assistant_messages_on_customer_id"
  end

  create_table "ai_assistant_provider_settings", force: :cascade do |t|
    t.text "api_key"
    t.text "config"
    t.datetime "created_at", null: false
    t.boolean "generation_active", default: false, null: false
    t.datetime "last_health_check_at"
    t.string "last_health_check_message"
    t.string "last_health_check_status"
    t.string "provider", null: false
    t.boolean "transcribe_active", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["generation_active"], name: "index_ai_assistant_provider_settings_single_generation", unique: true, where: "generation_active"
    t.index ["provider"], name: "index_ai_assistant_provider_settings_on_provider", unique: true
    t.index ["transcribe_active"], name: "index_ai_assistant_provider_settings_single_transcribe", unique: true, where: "transcribe_active"
  end

  create_table "ai_assistant_subsystem_builds", force: :cascade do |t|
    t.json "answers", default: [], null: false
    t.json "blueprint", default: {}, null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.json "questions", default: [], null: false
    t.json "results", default: {}, null: false
    t.string "stage", default: "journeys", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["conversation_id"], name: "ai_assistant_one_active_subsystem_build", unique: true, where: "status IN ('running','waiting_for_answers')"
    t.index ["conversation_id"], name: "index_ai_assistant_subsystem_builds_on_conversation_id"
    t.index ["customer_id"], name: "index_ai_assistant_subsystem_builds_on_customer_id"
    t.index ["user_id"], name: "index_ai_assistant_subsystem_builds_on_user_id"
  end

  create_table "authentication_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "event", null: false
    t.string "ip"
    t.json "metadata", default: {}, null: false
    t.string "user_agent"
    t.integer "user_id"
    t.index ["customer_id", "created_at"], name: "index_authentication_events_on_customer_id_and_created_at"
    t.index ["event", "created_at"], name: "index_authentication_events_on_event_and_created_at"
    t.index ["user_id", "created_at"], name: "index_authentication_events_on_user_id_and_created_at"
  end

  create_table "authentication_platform_settings", force: :cascade do |t|
    t.boolean "allow_customer_signup", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "billing_collection_attempts", force: :cascade do |t|
    t.bigint "billing_invoice_id", null: false
    t.bigint "billing_payment_method_id"
    t.datetime "claimed_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "failure_code"
    t.bigint "merchant_account_id", null: false
    t.integer "ordinal", null: false
    t.bigint "payment_id"
    t.datetime "reconcile_at"
    t.string "request_key", null: false
    t.string "state", default: "prepared", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["billing_invoice_id", "ordinal"], name: "billing_attempt_ordinal", unique: true
    t.index ["billing_invoice_id"], name: "billing_one_inflight_attempt", unique: true, where: "state IN ('prepared','submitting','pending','requires_action','unknown')"
    t.index ["billing_payment_method_id"], name: "index_billing_collection_attempts_on_billing_payment_method_id"
    t.index ["customer_id"], name: "index_billing_collection_attempts_on_customer_id"
    t.index ["merchant_account_id"], name: "index_billing_collection_attempts_on_merchant_account_id"
    t.index ["payment_id"], name: "index_billing_collection_attempts_on_payment_id", unique: true, where: "payment_id IS NOT NULL"
    t.index ["request_key"], name: "index_billing_collection_attempts_on_request_key", unique: true
    t.check_constraint "ordinal > 0", name: "billing_collection_attempts_integrity_0"
    t.check_constraint "state IN ('prepared','submitting','pending','requires_action','succeeded','failed','unknown')", name: "billing_collection_attempts_integrity_1"
  end

  create_table "billing_countable_items", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: false, null: false
    t.string "key", null: false
    t.string "label", null: false
    t.string "period", default: "total", null: false
    t.integer "position", default: 0, null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_billing_countable_items_on_key", unique: true
  end

  create_table "billing_coupon_redemptions", force: :cascade do |t|
    t.bigint "billing_coupon_id", null: false
    t.bigint "billing_subscription_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.integer "cycles_used", default: 0, null: false
    t.datetime "redeemed_at", null: false
    t.json "terms_snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["billing_coupon_id"], name: "index_billing_coupon_redemptions_on_billing_coupon_id"
    t.index ["billing_subscription_id"], name: "index_billing_coupon_redemptions_on_billing_subscription_id", unique: true
    t.index ["customer_id"], name: "index_billing_coupon_redemptions_on_customer_id"
    t.check_constraint "cycles_used >= 0", name: "billing_coupon_redemptions_integrity_0"
  end

  create_table "billing_coupons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "amount_off_cents"
    t.datetime "archived_at"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "discount_type", null: false
    t.string "duration", null: false
    t.integer "duration_in_cycles"
    t.integer "max_redemptions"
    t.string "name", null: false
    t.integer "percent_off"
    t.datetime "redeem_by"
    t.integer "times_redeemed", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_billing_coupons_on_active"
    t.index ["code"], name: "index_billing_coupons_on_code", unique: true
    t.check_constraint "discount_type != 'fixed' OR (amount_off_cents IS NOT NULL AND amount_off_cents > 0)", name: "billing_coupons_integrity_4"
    t.check_constraint "discount_type != 'fixed' OR (currency IS NOT NULL AND currency IN ('USD','CNY'))", name: "billing_coupons_integrity_1"
    t.check_constraint "discount_type != 'percent' OR (percent_off IS NOT NULL AND percent_off BETWEEN 1 AND 100)", name: "billing_coupons_integrity_3"
    t.check_constraint "discount_type IN ('percent','fixed') AND duration IN ('once','repeating','forever')", name: "billing_coupons_integrity_2"
    t.check_constraint "duration != 'repeating' OR (duration_in_cycles IS NOT NULL AND duration_in_cycles > 0)", name: "billing_coupons_integrity_5"
    t.check_constraint "max_redemptions IS NULL OR max_redemptions > 0", name: "billing_coupons_integrity_6"
    t.check_constraint "times_redeemed >= 0", name: "billing_coupons_integrity_0"
  end

  create_table "billing_invoice_line_items", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "billing_invoice_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "description", null: false
    t.string "kind", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_amount_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_invoice_id"], name: "index_billing_invoice_line_items_on_billing_invoice_id"
    t.index ["customer_id"], name: "index_billing_invoice_line_items_on_customer_id"
  end

  create_table "billing_invoice_sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.bigint "last_value", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_billing_invoice_sequences_on_customer_id", unique: true
    t.check_constraint "last_value >= 0", name: "billing_invoice_sequences_integrity_0"
  end

  create_table "billing_invoices", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.bigint "billing_coupon_id"
    t.bigint "billing_coupon_redemption_id"
    t.bigint "billing_plan_change_id"
    t.bigint "billing_subscription_id", null: false
    t.datetime "collection_claimed_at"
    t.string "collection_mode"
    t.datetime "collection_override_at"
    t.bigint "collection_override_by_id"
    t.string "collection_override_mode"
    t.string "collection_state", default: "ready", null: false
    t.integer "coupon_cycle_number"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.integer "discount_cents", default: 0, null: false
    t.datetime "due_at"
    t.datetime "entitlements_applied_at"
    t.string "failure_code"
    t.datetime "first_failed_at"
    t.string "idempotency_key", null: false
    t.datetime "issued_at"
    t.datetime "next_attempt_at"
    t.string "number"
    t.datetime "paid_at"
    t.bigint "payment_id"
    t.datetime "period_end"
    t.datetime "period_start"
    t.string "purpose", null: false
    t.bigint "settled_by_id"
    t.text "settlement_note"
    t.string "settlement_reference"
    t.string "settlement_review_code"
    t.string "settlement_source"
    t.string "status", default: "draft", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.json "terms_snapshot", default: {}, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["billing_coupon_redemption_id", "coupon_cycle_number"], name: "billing_one_invoice_per_coupon_cycle", unique: true, where: "coupon_cycle_number IS NOT NULL"
    t.index ["billing_plan_change_id"], name: "billing_one_proration_per_change", unique: true, where: "purpose = 'proration'"
    t.index ["billing_subscription_id"], name: "index_billing_invoices_on_billing_subscription_id"
    t.index ["collection_state", "next_attempt_at"], name: "billing_collection_population"
    t.index ["customer_id", "idempotency_key"], name: "billing_invoice_request_identity", unique: true
    t.index ["customer_id"], name: "index_billing_invoices_on_customer_id"
    t.index ["number"], name: "index_billing_invoices_on_number", unique: true
    t.index ["status", "next_attempt_at"], name: "index_billing_invoices_on_status_and_next_attempt_at"
    t.check_constraint "collection_state IN ('ready','manual','blocked','pending','requires_action','retry_wait','exhausted','settled','stopped')", name: "billing_invoices_integrity_2"
    t.check_constraint "coupon_cycle_number IS NULL OR coupon_cycle_number > 0", name: "billing_invoices_integrity_4"
    t.check_constraint "purpose IN ('initial','renewal','proration')", name: "billing_invoices_integrity_1"
    t.check_constraint "status IN ('draft','open','paid','void','uncollectible')", name: "billing_invoices_integrity_3"
    t.check_constraint "subtotal_cents >= 0 AND discount_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0 AND attempt_count >= 0", name: "billing_invoices_integrity_0"
  end

  create_table "billing_notices", force: :cascade do |t|
    t.bigint "billing_collection_attempt_id"
    t.bigint "billing_invoice_id"
    t.bigint "billing_subscription_id"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.datetime "enqueued_at"
    t.string "event_key", null: false
    t.string "kind", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_collection_attempt_id"], name: "index_billing_notices_on_billing_collection_attempt_id"
    t.index ["billing_invoice_id"], name: "index_billing_notices_on_billing_invoice_id"
    t.index ["billing_subscription_id"], name: "index_billing_notices_on_billing_subscription_id"
    t.index ["customer_id"], name: "index_billing_notices_on_customer_id"
    t.index ["event_key"], name: "index_billing_notices_on_event_key", unique: true
    t.check_constraint "state IN ('pending','enqueued')", name: "billing_notices_integrity_0"
  end

  create_table "billing_payment_methods", force: :cascade do |t|
    t.datetime "authorization_expires_at"
    t.string "authorization_reference"
    t.datetime "authorized_at"
    t.bigint "authorized_by_id"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "display_label"
    t.string "failure_code"
    t.boolean "is_default", default: false, null: false
    t.bigint "merchant_account_id"
    t.bigint "payments_subscription_id"
    t.string "provider", null: false
    t.datetime "removed_at"
    t.string "request_key", null: false
    t.boolean "requested_default", default: false, null: false
    t.integer "revocation_attempt_count", default: 0, null: false
    t.datetime "revocation_next_attempt_at"
    t.string "revocation_state", default: "none", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "request_key"], name: "billing_method_request_identity", unique: true
    t.index ["customer_id"], name: "index_billing_payment_methods_on_customer_id"
    t.index ["customer_id"], name: "index_billing_payment_methods_on_customer_id_active_default", unique: true, where: "is_default = TRUE AND status = 'active'"
    t.index ["merchant_account_id", "authorization_reference"], name: "billing_authorization_identity", unique: true, where: "authorization_reference IS NOT NULL"
    t.index ["payments_subscription_id"], name: "billing_one_method_per_mandate", unique: true, where: "payments_subscription_id IS NOT NULL"
    t.check_constraint "revocation_attempt_count >= 0", name: "billing_payment_methods_integrity_0"
    t.check_constraint "revocation_state IN ('none','pending','complete','failed')", name: "billing_payment_methods_integrity_2"
    t.check_constraint "status IN ('pending','active','failed','removed')", name: "billing_payment_methods_integrity_1"
  end

  create_table "billing_plan_changes", force: :cascade do |t|
    t.datetime "applied_at"
    t.bigint "billing_subscription_id", null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.datetime "effective_at", null: false
    t.bigint "from_plan_id", null: false
    t.json "from_snapshot", default: {}, null: false
    t.string "kind", null: false
    t.datetime "period_end", null: false
    t.datetime "period_start", null: false
    t.string "request_key", null: false
    t.string "status", null: false
    t.json "target_snapshot", default: {}, null: false
    t.bigint "to_plan_id", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_subscription_id"], name: "billing_one_outstanding_change", unique: true, where: "status IN ('awaiting_payment','scheduled')"
    t.index ["customer_id", "request_key"], name: "billing_change_request_identity", unique: true
    t.index ["from_plan_id"], name: "index_billing_plan_changes_on_from_plan_id"
    t.index ["to_plan_id"], name: "index_billing_plan_changes_on_to_plan_id"
    t.check_constraint "kind IN ('immediate','scheduled')", name: "billing_plan_changes_integrity_0"
    t.check_constraint "period_end > period_start", name: "billing_plan_changes_integrity_2"
    t.check_constraint "status IN ('awaiting_payment','scheduled','applied','cancelled','expired')", name: "billing_plan_changes_integrity_1"
  end

  create_table "billing_plan_limits", force: :cascade do |t|
    t.integer "billing_plan_id", null: false
    t.datetime "created_at", null: false
    t.string "item_key", null: false
    t.integer "limit_value", default: -1, null: false
    t.datetime "updated_at", null: false
    t.index ["billing_plan_id", "item_key"], name: "index_billing_plan_limits_on_billing_plan_id_and_item_key", unique: true
    t.index ["billing_plan_id"], name: "index_billing_plan_limits_on_billing_plan_id"
    t.check_constraint "limit_value >= -1", name: "billing_plan_limits_integrity_0"
  end

  create_table "billing_plans", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.decimal "amount_cny", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "amount_usd", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "archived_at"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "interval", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "trial_days", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_billing_plans_on_active"
    t.index ["code"], name: "index_billing_plans_on_code", unique: true
    t.index ["is_default"], name: "billing_one_default_plan", unique: true, where: "is_default = 1"
    t.index ["position"], name: "index_billing_plans_on_position"
    t.check_constraint "amount_usd >= 0 AND amount_cny >= 0 AND trial_days >= 0", name: "billing_plans_integrity_0"
    t.check_constraint "is_default = 0 OR (active = 1 AND archived_at IS NULL AND amount_usd = 0 AND amount_cny = 0 AND trial_days = 0)", name: "billing_plans_integrity_1"
  end

  create_table "billing_settings", force: :cascade do |t|
    t.string "collection_mode", default: "manual", null: false
    t.datetime "created_at", null: false
    t.json "dunning_schedule"
    t.integer "grace_period_days", default: 7, null: false
    t.integer "singleton_guard", default: 0, null: false
    t.integer "tax_rate_bps", default: 0, null: false
    t.integer "trial_ending_notice_days", default: 3, null: false
    t.datetime "updated_at", null: false
    t.index ["singleton_guard"], name: "index_billing_settings_singleton", unique: true
    t.check_constraint "tax_rate_bps BETWEEN 0 AND 10000 AND grace_period_days >= 0 AND trial_ending_notice_days >= 0", name: "billing_settings_integrity_0"
  end

  create_table "billing_subscriptions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "billing_anchor_day"
    t.integer "billing_anchor_month"
    t.bigint "billing_coupon_id"
    t.bigint "billing_plan_id", null: false
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.bigint "customer_id", null: false
    t.datetime "ended_at"
    t.string "interval", null: false
    t.datetime "past_due_at"
    t.json "plan_snapshot", default: {}, null: false
    t.string "request_key", null: false
    t.datetime "started_at"
    t.string "status", null: false
    t.datetime "trial_end"
    t.datetime "updated_at", null: false
    t.index ["billing_coupon_id"], name: "index_billing_subscriptions_on_billing_coupon_id"
    t.index ["billing_plan_id"], name: "index_billing_subscriptions_on_billing_plan_id"
    t.index ["customer_id", "request_key"], name: "billing_subscription_request_identity", unique: true
    t.index ["customer_id"], name: "index_billing_subscriptions_on_customer_id"
    t.index ["customer_id"], name: "index_billing_subscriptions_on_customer_id_live_unique", unique: true, where: "status IN ('pending','trialing','active','past_due','paused')"
    t.index ["status"], name: "index_billing_subscriptions_on_status"
    t.check_constraint "amount_cents >= 0", name: "billing_subscriptions_integrity_0"
    t.check_constraint "billing_anchor_day BETWEEN 1 AND 31 AND billing_anchor_month BETWEEN 1 AND 12", name: "billing_subscriptions_integrity_4"
    t.check_constraint "currency IN ('USD','CNY')", name: "billing_subscriptions_integrity_2"
    t.check_constraint "interval IN ('monthly','yearly')", name: "billing_subscriptions_integrity_3"
    t.check_constraint "status IN ('pending','trialing','active','past_due','paused','cancelled','expired')", name: "billing_subscriptions_integrity_1"
  end

  create_table "captcha_provider_settings", force: :cascade do |t|
    t.string "access_key_id"
    t.text "access_key_secret"
    t.text "config"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.string "fail_policy", default: "open", null: false
    t.datetime "last_health_check_at"
    t.string "last_health_check_message"
    t.string "last_health_check_status"
    t.string "provider", null: false
    t.decimal "score_threshold", precision: 4, scale: 3
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_captcha_provider_settings_single_active", unique: true, where: "enabled"
    t.index ["provider"], name: "index_captcha_provider_settings_on_provider", unique: true
  end

  create_table "captcha_url_throttles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.boolean "every_hit", default: false, null: false
    t.integer "limit_count"
    t.string "match_kind", null: false
    t.bigint "page_id"
    t.integer "period_seconds"
    t.boolean "skipped", default: false, null: false
    t.string "surface_key"
    t.datetime "updated_at", null: false
    t.string "url_pattern", null: false
    t.index ["customer_id"], name: "index_captcha_url_throttles_on_customer_id"
    t.index ["match_kind", "url_pattern"], name: "idx_captcha_url_throttles_kind_pattern", unique: true
    t.index ["page_id"], name: "index_captcha_url_throttles_on_page_id"
  end

  create_table "constant_customer_overrides", force: :cascade do |t|
    t.integer "constant_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.json "options", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["constant_id", "customer_id"], name: "idx_on_constant_id_customer_id_842f99d159", unique: true
    t.index ["customer_id"], name: "index_constant_customer_overrides_on_customer_id"
  end

  create_table "constants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "name", null: false
    t.json "options", default: []
    t.datetime "updated_at", null: false
    t.index ["customer_id", "name"], name: "index_constants_on_customer_id_and_name_for_customer_specific", unique: true, where: "customer_id IS NOT NULL"
    t.index ["customer_id"], name: "index_constants_on_customer_id"
    t.index ["name"], name: "index_constants_on_name"
    t.index ["name"], name: "index_constants_on_name_for_shared", unique: true, where: "customer_id IS NULL"
  end

  create_table "customer_feature_modules", force: :cascade do |t|
    t.text "configuration"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "enabled_at"
    t.integer "feature_module_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "feature_module_id"], name: "idx_customer_feature_modules_unique", unique: true
    t.index ["customer_id"], name: "index_customer_feature_modules_on_customer_id"
    t.index ["feature_module_id"], name: "index_customer_feature_modules_on_feature_module_id"
    t.index ["status"], name: "index_customer_feature_modules_on_status"
  end

  create_table "customers", force: :cascade do |t|
    t.text "address"
    t.string "alias"
    t.string "contact"
    t.datetime "created_at", null: false
    t.string "domain", limit: 253
    t.integer "industry"
    t.string "locale"
    t.string "name", null: false
    t.string "phone"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "tier", default: 0, null: false
    t.datetime "trial_used_at"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_customers_on_created_at"
    t.index ["domain"], name: "index_customers_on_domain", unique: true
    t.index ["industry"], name: "index_customers_on_industry"
    t.index ["name"], name: "index_customers_on_name"
    t.index ["status"], name: "index_customers_on_status"
    t.index ["tier"], name: "index_customers_on_tier"
  end

  create_table "email_backend_receipts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "credential_id", null: false
    t.bigint "customer_id"
    t.string "event_key", null: false
    t.json "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.string "vendor_message_id"
    t.index ["credential_id", "event_key"], name: "idx_email_backend_receipts_identity", unique: true
    t.index ["customer_id"], name: "index_email_backend_receipts_on_customer_id"
    t.index ["processed_at", "created_at"], name: "idx_email_backend_receipts_pending"
    t.index ["provider", "vendor_message_id"], name: "idx_email_backend_receipts_correlation"
  end

  create_table "email_credentials", force: :cascade do |t|
    t.string "authentication", default: "plain", null: false
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "dkim_domain"
    t.boolean "dkim_enabled", default: false, null: false
    t.text "dkim_private_key"
    t.string "dkim_selector"
    t.string "domain"
    t.boolean "enable_starttls", default: true, null: false
    t.string "host"
    t.string "mode", null: false
    t.text "password", null: false
    t.integer "port", default: 587, null: false
    t.string "provider", default: "smtp", null: false
    t.boolean "ssl", default: false, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.text "webhook_secret"
    t.index ["provider", "mode"], name: "index_email_credentials_on_provider_mode", unique: true
  end

  create_table "email_list_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "email_list_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["email_list_id", "user_id"], name: "index_email_list_memberships_on_email_list_id_and_user_id", unique: true
    t.index ["email_list_id"], name: "index_email_list_memberships_on_email_list_id"
    t.index ["user_id"], name: "index_email_list_memberships_on_user_id"
  end

  create_table "email_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "description"
    t.string "list_type", default: "static", null: false
    t.string "name", null: false
    t.json "segment_rules", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_email_lists_on_customer_id"
  end

  create_table "email_message_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "ip"
    t.integer "message_id", null: false
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "user_agent"
    t.index ["message_id", "event_type"], name: "index_email_message_events_on_message_id_and_event_type", unique: true, where: "event_type = 'open'"
    t.index ["message_id"], name: "index_email_message_events_on_message_id"
  end

  create_table "email_messages", force: :cascade do |t|
    t.string "bcc"
    t.text "body_html", null: false
    t.text "body_text"
    t.string "cc"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "delivered_at"
    t.integer "delivery_attempts", default: 0, null: false
    t.string "delivery_claim_token"
    t.datetime "delivery_claimed_at"
    t.datetime "delivery_due_at"
    t.datetime "delivery_enqueued_at"
    t.integer "email_send_activity_id"
    t.integer "email_template_id"
    t.string "failure_code"
    t.string "failure_message"
    t.string "from", null: false
    t.string "idempotency_key"
    t.string "message_type", default: "transactional", null: false
    t.json "metadata", default: {}, null: false
    t.string "provider"
    t.string "provider_message_id"
    t.string "reply_to"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.string "subject", null: false
    t.string "to", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "created_at"], name: "index_email_messages_on_customer_id_and_created_at"
    t.index ["customer_id", "idempotency_key"], name: "idx_email_messages_customer_idem", unique: true, where: "idempotency_key IS NOT NULL"
    t.index ["customer_id", "status"], name: "index_email_messages_on_customer_id_and_status"
    t.index ["email_send_activity_id", "created_at"], name: "index_email_messages_on_email_send_activity_id_and_created_at"
    t.index ["email_template_id"], name: "index_email_messages_on_email_template_id"
    t.index ["provider_message_id"], name: "index_email_messages_on_provider_message_id"
    t.index ["status", "delivery_due_at", "delivery_enqueued_at"], name: "idx_email_backend_dispatch_due"
  end

  create_table "email_send_activities", force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "deferred_reason"
    t.datetime "deferred_until"
    t.integer "email_template_id"
    t.string "fanout_claim_token"
    t.datetime "fanout_claimed_at"
    t.string "name", null: false
    t.datetime "progressed_at"
    t.string "recurrence_rule"
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.json "stats", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "status"], name: "index_email_send_activities_on_customer_id_and_status"
    t.index ["email_template_id"], name: "index_email_send_activities_on_email_template_id"
    t.index ["status", "claimed_at"], name: "index_email_send_activities_on_status_and_claimed_at"
    t.index ["status", "deferred_until"], name: "idx_email_backend_campaign_deferral"
    t.index ["status", "scheduled_at"], name: "index_email_send_activities_on_status_and_scheduled_at"
  end

  create_table "email_send_activity_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "email_list_id", null: false
    t.integer "email_send_activity_id", null: false
    t.datetime "updated_at", null: false
    t.index ["email_list_id"], name: "index_email_send_activity_lists_on_email_list_id"
    t.index ["email_send_activity_id", "email_list_id"], name: "idx_on_email_send_activity_id_email_list_id_ab92ed4a83", unique: true
    t.index ["email_send_activity_id"], name: "index_email_send_activity_lists_on_email_send_activity_id"
  end

  create_table "email_suppressions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "email", null: false
    t.string "provider"
    t.string "reason"
    t.index ["customer_id", "email"], name: "index_email_suppressions_on_customer_id_and_email", unique: true
    t.index ["email"], name: "index_email_suppressions_global_unique", unique: true, where: "customer_id IS NULL"
    t.index ["email"], name: "index_email_suppressions_on_email"
  end

  create_table "email_template_contents", force: :cascade do |t|
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "payload", null: false
    t.index ["customer_id", "content_hash"], name: "index_email_template_contents_on_customer_and_hash", unique: true
    t.index ["customer_id"], name: "index_email_template_contents_on_customer_id"
  end

  create_table "email_template_tokens", force: :cascade do |t|
    t.string "attribute_slug"
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.integer "entity_id"
    t.string "label", null: false
    t.string "source_key"
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["customer_id", "entity_id", "attribute_slug"], name: "idx_email_template_tokens_customer_entity_attr", unique: true
    t.index ["customer_id"], name: "index_email_template_tokens_on_customer_id"
    t.index ["source_key"], name: "idx_email_template_tokens_platform_source_key", unique: true
    t.index ["uuid"], name: "index_email_template_tokens_on_uuid", unique: true
  end

  create_table "email_template_versions", force: :cascade do |t|
    t.integer "based_on_version_id"
    t.integer "content_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "description"
    t.integer "email_template_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["content_id"], name: "index_email_template_versions_on_content_id"
    t.index ["customer_id"], name: "index_email_template_versions_on_customer_id"
    t.index ["email_template_id", "version_number"], name: "index_email_template_versions_on_template_id_and_version_number", unique: true
  end

  create_table "email_templates", force: :cascade do |t|
    t.text "body_html", null: false
    t.text "body_text"
    t.datetime "created_at", null: false
    t.integer "current_version_id"
    t.integer "customer_id", null: false
    t.string "editor_type", default: "code", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_email_templates_on_customer_id"
  end

  create_table "entities", force: :cascade do |t|
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "current_version_id"
    t.integer "customer_id"
    t.string "display_label", default: "", null: false
    t.string "extended_model"
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_entities_on_category"
    t.index ["created_at"], name: "index_entities_on_created_at"
    t.index ["current_version_id"], name: "index_entities_on_current_version_id"
    t.index ["customer_id", "category"], name: "index_entities_on_customer_id_and_category"
    t.index ["customer_id"], name: "index_entities_on_customer_id"
    t.index ["name"], name: "index_entities_on_name"
    t.index ["status"], name: "index_entities_on_status"
  end

  create_table "entity_customer_heads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_version_id", null: false
    t.integer "customer_id", null: false
    t.integer "entity_id", null: false
    t.datetime "updated_at", null: false
    t.index ["current_version_id"], name: "index_entity_customer_heads_on_current_version_id"
    t.index ["entity_id", "customer_id"], name: "index_entity_customer_heads_on_entity_id_and_customer_id", unique: true
  end

  create_table "entity_definition_contents", force: :cascade do |t|
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.text "payload", null: false
    t.index ["customer_id", "content_hash"], name: "index_entity_definition_contents_on_customer_and_hash", unique: true
    t.index ["customer_id"], name: "index_entity_definition_contents_on_customer_id"
  end

  create_table "entity_domain_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "entity_domain_id", null: false
    t.integer "entity_id", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "entity_id"], name: "idx_entity_domain_memberships_customer_entity", unique: true
    t.index ["entity_domain_id"], name: "index_entity_domain_memberships_on_entity_domain_id"
    t.index ["entity_id"], name: "index_entity_domain_memberships_on_entity_id"
  end

  create_table "entity_domains", force: :cascade do |t|
    t.string "color", default: "slate", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "customer_id, LOWER(name)", name: "idx_entity_domains_customer_name", unique: true
  end

  create_table "entity_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "data"
    t.integer "entity_id", null: false
    t.integer "entity_version_number"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["created_at"], name: "index_entity_entries_on_created_at"
    t.index ["customer_id", "entity_id"], name: "index_entity_entries_on_customer_id_and_entity_id"
    t.index ["customer_id", "user_id"], name: "index_entity_entries_on_customer_id_and_user_id"
    t.index ["customer_id"], name: "index_entity_entries_on_customer_id"
    t.index ["entity_id", "user_id"], name: "idx_entity_entries_person_link", unique: true, where: "user_id IS NOT NULL"
    t.index ["entity_id"], name: "index_entity_entries_on_entity_id"
  end

  create_table "entity_index_settings", force: :cascade do |t|
    t.text "config", default: "{}", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.bigint "entity_id", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "entity_id"], name: "idx_entity_index_settings_on_customer_and_entity", unique: true
    t.index ["customer_id"], name: "index_entity_index_settings_on_customer_id"
    t.index ["entity_id"], name: "index_entity_index_settings_on_entity_id"
  end

  create_table "entity_versions", force: :cascade do |t|
    t.integer "based_on_version_id"
    t.integer "content_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "description"
    t.integer "entity_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["based_on_version_id"], name: "index_entity_versions_on_based_on_version_id"
    t.index ["content_id"], name: "index_entity_versions_on_content_id"
    t.index ["customer_id"], name: "index_entity_versions_on_customer_id"
    t.index ["entity_id", "customer_id", "version_number"], name: "index_entity_versions_customer_line", unique: true, where: "customer_id IS NOT NULL"
    t.index ["entity_id", "version_number"], name: "index_entity_versions_global_line", unique: true, where: "customer_id IS NULL"
    t.index ["entity_id"], name: "index_entity_versions_on_entity_id"
  end

  create_table "feature_module_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "entity_entry_id"
    t.text "error_message"
    t.integer "feature_module_id", null: false
    t.text "request_data"
    t.text "response_data"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_feature_module_logs_on_action"
    t.index ["customer_id", "feature_module_id"], name: "idx_feature_module_logs_customer_module"
    t.index ["customer_id"], name: "index_feature_module_logs_on_customer_id"
    t.index ["entity_entry_id"], name: "index_feature_module_logs_on_entity_entry_id"
    t.index ["feature_module_id"], name: "index_feature_module_logs_on_feature_module_id"
    t.index ["status"], name: "index_feature_module_logs_on_status"
  end

  create_table "feature_modules", force: :cascade do |t|
    t.text "configuration_schema"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "extendable_attributes"
    t.text "extendable_models"
    t.boolean "handoff_enabled", default: false, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.boolean "required", default: false, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["key"], name: "index_feature_modules_on_key", unique: true
    t.index ["status"], name: "index_feature_modules_on_status"
  end

  create_table "field_templates", force: :cascade do |t|
    t.boolean "built_in", default: false, null: false
    t.string "category"
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "built_in"], name: "index_field_templates_on_customer_id_and_built_in"
    t.index ["customer_id", "category"], name: "index_field_templates_on_customer_id_and_category"
    t.index ["customer_id"], name: "index_field_templates_on_customer_id"
  end

  create_table "flowchart_audit_events", force: :cascade do |t|
    t.integer "actor_user_id"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "event_type", null: false
    t.integer "flowchart_id"
    t.string "ip"
    t.json "metadata", default: {}, null: false
    t.string "resource_id"
    t.string "resource_type"
    t.string "severity", default: "info", null: false
    t.text "user_agent"
    t.index ["customer_id"], name: "index_flowchart_audit_events_on_customer_id"
  end

  create_table "flowchart_configuration_contents", force: :cascade do |t|
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.text "payload", null: false
    t.index ["customer_id", "content_hash"], name: "index_flowchart_configuration_contents_on_customer_and_hash", unique: true
    t.index ["customer_id"], name: "index_flowchart_configuration_contents_on_customer_id"
  end

  create_table "flowchart_customer_heads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_version_id", null: false
    t.integer "customer_id", null: false
    t.integer "flowchart_id", null: false
    t.datetime "updated_at", null: false
    t.index ["current_version_id"], name: "index_flowchart_customer_heads_on_current_version_id"
    t.index ["flowchart_id", "customer_id"], name: "index_flowchart_customer_heads_on_flowchart_id_and_customer_id", unique: true
  end

  create_table "flowchart_notifications", force: :cascade do |t|
    t.json "body", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "page_id"
    t.datetime "read_at"
    t.json "title", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["customer_id"], name: "index_flowchart_notifications_on_customer_id"
  end

  create_table "flowchart_sequences", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.integer "last_value", default: 0, null: false
    t.string "name", null: false
    t.string "period", null: false
    t.index ["customer_id", "name", "period"], name: "index_flowchart_sequences_on_customer_name_period", unique: true
    t.index ["customer_id"], name: "index_flowchart_sequences_on_customer_id"
  end

  create_table "flowchart_versions", force: :cascade do |t|
    t.bigint "based_on_version_id"
    t.integer "content_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "description"
    t.integer "flowchart_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["based_on_version_id"], name: "index_flowchart_versions_on_based_on_version_id"
    t.index ["content_id"], name: "index_flowchart_versions_on_content_id"
    t.index ["customer_id"], name: "index_flowchart_versions_on_customer_id"
    t.index ["flowchart_id", "customer_id", "version_number"], name: "index_flowchart_versions_customer_line", unique: true, where: "customer_id IS NOT NULL"
    t.index ["flowchart_id", "version_number"], name: "index_flowchart_versions_global_line", unique: true, where: "customer_id IS NULL"
    t.index ["flowchart_id"], name: "index_flowchart_versions_on_flowchart_id"
  end

  create_table "flowcharts", force: :cascade do |t|
    t.text "activity"
    t.datetime "created_at", null: false
    t.bigint "current_version_id"
    t.integer "customer_id"
    t.text "description"
    t.integer "launched_version_id"
    t.string "name", null: false
    t.integer "status", default: 2, null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["created_at"], name: "index_flowcharts_on_created_at"
    t.index ["current_version_id"], name: "index_flowcharts_on_current_version_id"
    t.index ["customer_id", "uuid"], name: "index_flowcharts_on_customer_id_and_uuid_for_custom", unique: true, where: "customer_id IS NOT NULL"
    t.index ["customer_id"], name: "index_flowcharts_on_customer_id"
    t.index ["launched_version_id"], name: "index_flowcharts_on_launched_version_id"
    t.index ["name"], name: "index_flowcharts_on_name"
    t.index ["status"], name: "index_flowcharts_on_status"
    t.index ["uuid"], name: "index_flowcharts_on_uuid", unique: true
  end

  create_table "industry_template_mappings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "industry", null: false
    t.string "template_key", null: false
    t.datetime "updated_at", null: false
    t.index ["industry", "template_key"], name: "idx_industry_template_unique", unique: true
    t.index ["industry"], name: "index_industry_template_mappings_on_industry"
    t.index ["template_key"], name: "index_industry_template_mappings_on_template_key"
  end

  create_table "journey_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "current_step"
    t.integer "customer_id", null: false
    t.datetime "expires_at", null: false
    t.integer "journey_id"
    t.text "state"
    t.integer "status", default: 0, null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["customer_id", "user_id"], name: "index_journey_runs_on_customer_id_and_user_id"
    t.index ["expires_at"], name: "index_journey_runs_on_expires_at"
    t.index ["journey_id"], name: "index_journey_runs_on_journey_id"
    t.index ["token_digest"], name: "index_journey_runs_on_token_digest", unique: true
  end

  create_table "journeys", force: :cascade do |t|
    t.boolean "audience_admin", default: true, null: false
    t.boolean "audience_member", default: false, null: false
    t.boolean "audience_public", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "definition"
    t.text "description"
    t.integer "entity_domain_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "key"], name: "index_journeys_on_customer_id_and_key", unique: true
    t.index ["customer_id", "status"], name: "index_journeys_on_customer_id_and_status"
    t.index ["entity_domain_id"], name: "index_journeys_on_entity_domain_id"
  end

  create_table "member_surface_settings", force: :cascade do |t|
    t.text "config", default: "{}", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.boolean "enabled"
    t.integer "position", default: 0, null: false
    t.string "source_key"
    t.string "surface_key", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "source_key"], name: "idx_member_surface_settings_on_customer_and_source"
    t.index ["customer_id", "surface_key"], name: "idx_member_surface_settings_on_customer_and_key", unique: true
    t.index ["customer_id"], name: "index_member_surface_settings_on_customer_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.datetime "family_started_at"
    t.string "refresh_token"
    t.integer "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "operation_invocations", force: :cascade do |t|
    t.string "channel", null: false
    t.datetime "confirmed_at"
    t.integer "confirmed_by_id"
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "duration_ms"
    t.bigint "generation_id"
    t.string "idempotency_key"
    t.json "input", default: {}, null: false
    t.string "input_digest"
    t.string "operation", null: false
    t.integer "operation_version", null: false
    t.json "plan", default: [], null: false
    t.json "result", default: {}, null: false
    t.json "snapshot", default: {}, null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.json "violations", default: [], null: false
    t.index ["confirmed_by_id"], name: "index_operation_invocations_on_confirmed_by_id"
    t.index ["conversation_id"], name: "index_operation_invocations_on_conversation_id"
    t.index ["customer_id", "idempotency_key"], name: "idx_operation_invocations_idempotency", unique: true, where: "idempotency_key IS NOT NULL"
    t.index ["customer_id", "operation", "created_at"], name: "idx_operation_invocations_directory"
    t.index ["customer_id"], name: "index_operation_invocations_on_customer_id"
    t.index ["generation_id"], name: "index_operation_invocations_on_generation_id"
    t.index ["user_id"], name: "index_operation_invocations_on_user_id"
  end

  create_table "page_configuration_contents", force: :cascade do |t|
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.text "payload", null: false
    t.index ["customer_id", "content_hash"], name: "index_page_configuration_contents_on_customer_and_hash", unique: true
    t.index ["customer_id"], name: "index_page_configuration_contents_on_customer_id"
  end

  create_table "page_customer_heads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_version_id", null: false
    t.integer "customer_id", null: false
    t.integer "page_id", null: false
    t.datetime "updated_at", null: false
    t.index ["current_version_id"], name: "index_page_customer_heads_on_current_version_id"
    t.index ["page_id", "customer_id"], name: "index_page_customer_heads_on_page_id_and_customer_id", unique: true
  end

  create_table "page_shortcuts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "path", null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "path"], name: "index_page_shortcuts_on_customer_id_and_path", unique: true
    t.index ["customer_id"], name: "index_page_shortcuts_on_customer_id"
    t.index ["target_type", "target_id"], name: "index_page_shortcuts_on_target_type_and_target_id"
    t.check_constraint "substr(path, 1, 1) = '/'", name: "page_shortcuts_absolute_path"
    t.check_constraint "target_type IN ('WebsitePage', 'Page')", name: "page_shortcuts_target_type"
  end

  create_table "page_versions", force: :cascade do |t|
    t.integer "based_on_version_id"
    t.integer "content_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "description"
    t.integer "page_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["based_on_version_id"], name: "index_page_versions_on_based_on_version_id"
    t.index ["content_id"], name: "index_page_versions_on_content_id"
    t.index ["customer_id"], name: "index_page_versions_on_customer_id"
    t.index ["page_id", "customer_id", "version_number"], name: "index_page_versions_customer_line", unique: true, where: "customer_id IS NOT NULL"
    t.index ["page_id", "version_number"], name: "index_page_versions_global_line", unique: true, where: "customer_id IS NULL"
    t.index ["page_id"], name: "index_page_versions_on_page_id"
  end

  create_table "pages", force: :cascade do |t|
    t.string "action_key"
    t.boolean "audience_admin", default: true, null: false
    t.boolean "audience_member", default: false, null: false
    t.boolean "audience_public", default: false, null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "current_version_id"
    t.integer "customer_id"
    t.text "description"
    t.integer "entity_version_id"
    t.integer "flowchart_id"
    t.boolean "launched", default: false, null: false
    t.string "name", null: false
    t.string "public_uuid"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_pages_on_created_at"
    t.index ["current_version_id"], name: "index_pages_on_current_version_id"
    t.index ["customer_id", "action_key"], name: "index_pages_on_customer_id_and_action_key"
    t.index ["customer_id", "entity_version_id"], name: "index_pages_on_customer_entity_version", unique: true, where: "entity_version_id IS NOT NULL AND customer_id IS NOT NULL AND status = 0"
    t.index ["customer_id"], name: "index_pages_on_customer_id"
    t.index ["entity_version_id"], name: "index_pages_on_shared_entity_version", unique: true, where: "entity_version_id IS NOT NULL AND customer_id IS NULL AND status = 0"
    t.index ["flowchart_id"], name: "index_pages_on_flowchart_id"
    t.index ["public_uuid"], name: "index_pages_on_public_uuid", unique: true
    t.index ["status"], name: "index_pages_on_status"
  end

  create_table "payment_default_gateways", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_default_gateways_on_customer_id", unique: true
  end

  create_table "payment_disputes", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "opened_at"
    t.integer "payment_id", null: false
    t.string "provider", null: false
    t.string "psp_dispute_id", null: false
    t.json "raw", default: {}, null: false
    t.string "reason"
    t.datetime "resolved_at"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_disputes_on_customer_id"
    t.index ["payment_id"], name: "index_payment_disputes_on_payment_id"
    t.index ["provider", "psp_dispute_id"], name: "idx_payment_disputes_on_provider_and_dispute", unique: true
  end

  create_table "payment_merchant_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "credentials"
    t.integer "customer_id", null: false
    t.string "merchant_id", null: false
    t.string "mode", default: "sandbox", null: false
    t.string "notify_url_override"
    t.string "provider", null: false
    t.string "status", default: "disabled", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "provider", "mode"], name: "idx_payment_accounts_on_cust_prov_mode", unique: true
    t.index ["customer_id"], name: "index_payment_merchant_accounts_on_customer_id"
    t.index ["provider", "merchant_id"], name: "idx_payment_accounts_on_prov_mch", unique: true
  end

  create_table "payment_methods", force: :cascade do |t|
    t.bigint "billing_authorized_by_id"
    t.bigint "billing_customer_id"
    t.string "brand"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "exp_month"
    t.integer "exp_year"
    t.boolean "is_default", default: false, null: false
    t.string "last4"
    t.string "provider", null: false
    t.string "psp_customer_id"
    t.string "psp_payment_method_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["billing_customer_id"], name: "index_payment_methods_on_billing_customer_id"
    t.index ["customer_id", "user_id"], name: "index_payment_methods_on_customer_id_and_user_id"
    t.index ["provider", "psp_payment_method_id"], name: "index_payment_methods_on_provider_and_psp_payment_method_id", unique: true
    t.check_constraint "(user_id IS NOT NULL AND billing_customer_id IS NULL AND billing_authorized_by_id IS NULL) OR (user_id IS NULL AND customer_id = 81721200 AND billing_customer_id IS NOT NULL AND billing_authorized_by_id IS NOT NULL)", name: "payment_methods_integrity_0"
  end

  create_table "payment_orders", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.integer "customer_id", null: false
    t.datetime "expires_at"
    t.string "external_ref", null: false
    t.json "metadata", default: {}, null: false
    t.json "on_success", default: {}, null: false
    t.datetime "paid_at"
    t.string "status", default: "pending", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "external_ref"], name: "index_payment_orders_on_customer_id_and_external_ref", unique: true
    t.index ["customer_id"], name: "index_payment_orders_on_customer_id"
    t.index ["status"], name: "index_payment_orders_on_status"
  end

  create_table "payment_platform_gateways", force: :cascade do |t|
    t.boolean "available", default: false, null: false
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_payment_platform_gateways_on_provider", unique: true
  end

  create_table "payment_reconciliation_bills", force: :cascade do |t|
    t.date "bill_date", null: false
    t.string "bill_type", default: "all", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "discrepancy_count", default: 0, null: false
    t.string "provider", null: false
    t.json "raw_summary", default: {}, null: false
    t.string "status", default: "downloading", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "provider", "bill_date", "bill_type"], name: "idx_recon_bills_on_cust_prov_date_type", unique: true
    t.index ["customer_id"], name: "index_payment_reconciliation_bills_on_customer_id"
  end

  create_table "payment_refunds", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "failed_at"
    t.string "out_refund_no", null: false
    t.integer "payment_id", null: false
    t.string "psp_refund_id"
    t.json "raw_notify", default: {}, null: false
    t.string "reason"
    t.datetime "requested_at"
    t.string "status", default: "requested", null: false
    t.datetime "succeeded_at"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_refunds_on_customer_id"
    t.index ["out_refund_no"], name: "index_payment_refunds_on_out_refund_no", unique: true
    t.index ["payment_id"], name: "index_payment_refunds_on_payment_id"
  end

  create_table "payment_subscriptions", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "cancelled_at"
    t.datetime "charge_claimed_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "cny", null: false
    t.integer "customer_id", null: false
    t.string "cycle", null: false
    t.string "external_ref", null: false
    t.string "managed_by", default: "payments", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "next_charge_at"
    t.integer "payment_method_id"
    t.string "plan_name", null: false
    t.string "provider", null: false
    t.string "psp_agreement_id"
    t.datetime "signed_at"
    t.string "status", default: "pending_sign", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "external_ref"], name: "index_payment_subscriptions_on_customer_id_and_external_ref", unique: true
    t.index ["customer_id"], name: "index_payment_subscriptions_on_customer_id"
    t.index ["managed_by", "status", "next_charge_at"], name: "payment_subscription_collection_owner"
    t.index ["payment_method_id"], name: "index_payment_subscriptions_on_payment_method_id"
    t.index ["provider", "psp_agreement_id"], name: "index_payment_subscriptions_on_provider_and_psp_agreement_id", unique: true, where: "psp_agreement_id IS NOT NULL"
    t.check_constraint "managed_by != 'billing' OR next_charge_at IS NULL", name: "payment_subscriptions_integrity_1"
    t.check_constraint "managed_by IN ('payments','billing')", name: "payment_subscriptions_integrity_0"
  end

  create_table "payment_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "event_type"
    t.json "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "provider", null: false
    t.string "psp_event_id", null: false
    t.string "signing_merchant_id"
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_webhook_events_on_customer_id"
    t.index ["provider", "psp_event_id"], name: "idx_payment_webhook_events_on_provider_and_event", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "failure_reason"
    t.string "flow", null: false
    t.string "handoff_token"
    t.string "out_trade_no", null: false
    t.datetime "paid_at"
    t.integer "payment_order_id", null: false
    t.json "prepay_payload", default: {}, null: false
    t.string "provider", null: false
    t.string "psp_transaction_id"
    t.json "raw_notify", default: {}, null: false
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["customer_id"], name: "index_payments_on_customer_id"
    t.index ["out_trade_no"], name: "index_payments_on_out_trade_no", unique: true
    t.index ["payment_order_id"], name: "index_payments_on_payment_order_id"
    t.index ["provider", "psp_transaction_id"], name: "index_payments_on_provider_and_psp_transaction_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "people_pending_claims", force: :cascade do |t|
    t.json "continuation"
    t.datetime "created_at", null: false
    t.boolean "created_user", default: false, null: false
    t.integer "customer_id", null: false
    t.integer "entity_entry_id"
    t.datetime "expires_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["customer_id"], name: "index_people_pending_claims_on_customer_id"
    t.index ["entity_entry_id"], name: "index_people_pending_claims_on_entity_entry_id"
    t.index ["expires_at"], name: "index_people_pending_claims_on_expires_at"
    t.index ["user_id"], name: "index_people_pending_claims_on_user_id", unique: true
  end

  create_table "platform_announcement_dismissals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "platform_announcement_id", null: false
    t.bigint "user_id", null: false
    t.index ["platform_announcement_id"], name: "idx_on_platform_announcement_id_49a2143c2e"
    t.index ["user_id", "customer_id", "platform_announcement_id"], name: "idx_platform_announcement_dismissals_unique", unique: true
  end

  create_table "platform_announcement_reads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.integer "platform_announcement_id", null: false
    t.bigint "user_id", null: false
    t.index ["platform_announcement_id"], name: "index_platform_announcement_reads_on_platform_announcement_id"
    t.index ["user_id", "customer_id", "platform_announcement_id"], name: "idx_platform_announcement_reads_unique", unique: true
  end

  create_table "platform_announcements", force: :cascade do |t|
    t.string "audience", default: "all", null: false
    t.text "body_en", null: false
    t.text "body_zh", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "ends_at"
    t.datetime "left_live_at"
    t.string "link_url"
    t.string "severity", default: "info", null: false
    t.datetime "starts_at"
    t.string "status", default: "draft", null: false
    t.json "target_rules", default: {}, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_platform_announcements_on_deleted_at"
    t.index ["left_live_at"], name: "index_platform_announcements_on_left_live_at"
    t.index ["status", "starts_at", "ends_at"], name: "idx_platform_announcements_live"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.bigint "subject_id"
    t.string "subject_key"
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id", "subject_type", "subject_id"], name: "idx_on_role_id_subject_type_subject_id_ab299f7286"
    t.index ["role_id", "subject_type", "subject_key"], name: "idx_on_role_id_subject_type_subject_key_0b3de35d91"
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
    t.check_constraint "subject_key IS NOT NULL OR subject_id IS NOT NULL", name: "role_permissions_subject_present"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.text "description"
    t.string "key", null: false
    t.boolean "locked_grants", default: false, null: false
    t.string "name", null: false
    t.boolean "system", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "key"], name: "index_roles_on_customer_id_and_key", unique: true
    t.index ["customer_id"], name: "index_roles_on_customer_id"
  end

  create_table "sms_backend_receipts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "credential_id", null: false
    t.bigint "customer_id"
    t.string "event_key", null: false
    t.json "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.string "vendor_message_id"
    t.index ["credential_id", "event_key"], name: "idx_sms_backend_receipts_identity", unique: true
    t.index ["customer_id"], name: "index_sms_backend_receipts_on_customer_id"
    t.index ["processed_at", "created_at"], name: "idx_sms_backend_receipts_pending"
    t.index ["provider", "vendor_message_id"], name: "idx_sms_backend_receipts_correlation"
  end

  create_table "sms_campaign_recipients", force: :cascade do |t|
    t.datetime "admitted_at"
    t.integer "campaign_id", null: false
    t.integer "contact_id", null: false
    t.json "contact_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "deferral_reason"
    t.datetime "delivery_due_at"
    t.integer "message_id"
    t.string "phone_e164", null: false
    t.datetime "processed_at"
    t.string "skip_reason"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.json "vars", default: {}, null: false
    t.index ["campaign_id", "contact_id"], name: "index_sms_campaign_recipients_on_campaign_id_and_contact_id", unique: true
    t.index ["campaign_id", "phone_e164"], name: "index_sms_campaign_recipients_on_campaign_id_and_phone_e164", unique: true
    t.index ["campaign_id", "status", "delivery_due_at", "id"], name: "idx_sms_recipients_due"
    t.index ["campaign_id"], name: "index_sms_campaign_recipients_on_campaign_id"
    t.index ["contact_id"], name: "index_sms_campaign_recipients_on_contact_id"
    t.index ["customer_id", "phone_e164", "admitted_at"], name: "idx_sms_recipients_admissions"
    t.index ["customer_id"], name: "index_sms_campaign_recipients_on_customer_id"
    t.index ["message_id"], name: "index_sms_campaign_recipients_on_message_id", unique: true, where: "message_id IS NOT NULL"
  end

  create_table "sms_campaigns", force: :cascade do |t|
    t.json "audience_snapshot", default: {}, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.integer "customer_id", null: false
    t.integer "deadline_hours", default: 24, null: false
    t.datetime "expires_at"
    t.string "failure_code"
    t.datetime "finished_at"
    t.integer "frequency_window_hours", default: 24, null: false
    t.datetime "heartbeat_at"
    t.datetime "launched_at"
    t.integer "launched_by_id"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.integer "quiet_hours_end", default: 9, null: false
    t.integer "quiet_hours_start", default: 21, null: false
    t.datetime "run_lease_expires_at"
    t.string "run_token"
    t.datetime "scheduled_at"
    t.integer "segment_id"
    t.integer "send_rate_per_minute", default: 60, null: false
    t.string "send_timing", default: "immediate", null: false
    t.json "settings_snapshot", default: {}, null: false
    t.datetime "started_at"
    t.json "stats", default: {}, null: false
    t.datetime "stats_refreshed_at"
    t.string "status", default: "draft", null: false
    t.integer "template_id"
    t.string "timezone", default: "Asia/Shanghai", null: false
    t.datetime "updated_at", null: false
    t.json "variable_map", default: {}, null: false
    t.index ["created_by_id"], name: "index_sms_campaigns_on_created_by_id"
    t.index ["customer_id", "status", "created_at"], name: "idx_sms_campaigns_directory"
    t.index ["customer_id"], name: "index_sms_campaigns_on_customer_id"
    t.index ["launched_by_id"], name: "index_sms_campaigns_on_launched_by_id"
    t.index ["segment_id"], name: "index_sms_campaigns_on_segment_id"
    t.index ["status", "run_lease_expires_at"], name: "index_sms_campaigns_on_status_and_run_lease_expires_at"
    t.index ["status", "scheduled_at"], name: "index_sms_campaigns_on_status_and_scheduled_at"
    t.index ["template_id"], name: "index_sms_campaigns_on_template_id"
  end

  create_table "sms_consent_events", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_user_id"
    t.integer "contact_id", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "event_key", null: false
    t.json "evidence", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "phone_e164", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_user_id"], name: "index_sms_consent_events_on_actor_user_id"
    t.index ["contact_id"], name: "index_sms_consent_events_on_contact_id"
    t.index ["customer_id", "contact_id", "id"], name: "idx_sms_consent_contact"
    t.index ["customer_id", "event_key"], name: "index_sms_consent_events_on_customer_id_and_event_key", unique: true
    t.index ["customer_id", "phone_e164", "id"], name: "idx_sms_consent_phone"
    t.index ["customer_id"], name: "index_sms_consent_events_on_customer_id"
  end

  create_table "sms_contacts", force: :cascade do |t|
    t.datetime "consent_changed_at"
    t.string "consent_status", default: "unknown", null: false
    t.string "country_code", default: "CN", null: false
    t.datetime "created_at", null: false
    t.json "custom_attributes", default: {}, null: false
    t.integer "customer_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name"
    t.string "phone_e164", null: false
    t.integer "source_entity_id"
    t.integer "source_entry_id"
    t.string "source_kind", default: "manual", null: false
    t.json "source_mapping", default: {}, null: false
    t.string "status", default: "active", null: false
    t.datetime "synced_at"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "phone_e164"], name: "index_sms_contacts_on_customer_id_and_phone_e164", unique: true
    t.index ["customer_id", "source_entity_id", "source_entry_id"], name: "idx_sms_contacts_source", unique: true, where: "source_entity_id IS NOT NULL AND source_entry_id IS NOT NULL"
    t.index ["customer_id", "status", "consent_status"], name: "idx_sms_contacts_permission"
    t.index ["customer_id"], name: "index_sms_contacts_on_customer_id"
    t.index ["source_entity_id"], name: "index_sms_contacts_on_source_entity_id"
    t.index ["source_entry_id"], name: "index_sms_contacts_on_source_entry_id"
  end

  create_table "sms_credentials", force: :cascade do |t|
    t.string "access_key_id", null: false
    t.text "access_key_secret", null: false
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "dispatch_next_at"
    t.string "mode", null: false
    t.string "provider", default: "aliyun", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "mode"], name: "index_sms_credentials_on_provider_mode", unique: true
  end

  create_table "sms_messages", force: :cascade do |t|
    t.integer "campaign_id"
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "delivered_at"
    t.integer "delivery_attempts", default: 0, null: false
    t.string "delivery_claim_token"
    t.datetime "delivery_claimed_at"
    t.datetime "delivery_due_at"
    t.datetime "delivery_enqueued_at"
    t.datetime "dispatch_started_at"
    t.datetime "expires_at"
    t.string "failure_code"
    t.string "failure_message"
    t.string "idempotency_key"
    t.json "metadata", default: {}, null: false
    t.string "provider"
    t.json "raw_response", default: {}, null: false
    t.datetime "sent_at"
    t.integer "sms_template_id"
    t.string "status", default: "queued", null: false
    t.string "template_key", null: false
    t.string "to", null: false
    t.datetime "updated_at", null: false
    t.json "vars", default: {}, null: false
    t.string "vendor_message_id"
    t.index ["campaign_id"], name: "index_sms_messages_on_campaign_id"
    t.index ["contact_id"], name: "index_sms_messages_on_contact_id"
    t.index ["customer_id", "created_at"], name: "idx_sms_messages_daily_cap"
    t.index ["customer_id", "idempotency_key"], name: "idx_sms_messages_customer_idem", unique: true, where: "idempotency_key IS NOT NULL"
    t.index ["customer_id", "to", "created_at"], name: "idx_sms_backend_phone_window"
    t.index ["customer_id"], name: "index_sms_messages_on_customer_id"
    t.index ["sms_template_id"], name: "index_sms_messages_on_sms_template_id"
    t.index ["status", "dispatch_started_at", "delivery_due_at"], name: "idx_sms_messages_due"
    t.index ["status", "dispatch_started_at", "delivery_enqueued_at"], name: "idx_sms_delivery_outbox"
    t.index ["status"], name: "index_sms_messages_on_status"
    t.index ["to", "template_key", "created_at"], name: "idx_sms_messages_rate_limit"
    t.index ["vendor_message_id"], name: "index_sms_messages_on_vendor_message_id"
  end

  create_table "sms_opt_outs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id"
    t.string "phone_e164", null: false
    t.string "provider"
    t.string "reason"
    t.index ["customer_id", "phone_e164"], name: "index_sms_opt_outs_on_customer_id_and_phone_e164", unique: true
    t.index ["phone_e164"], name: "index_sms_opt_outs_global_unique", unique: true, where: "customer_id IS NULL"
    t.index ["phone_e164"], name: "index_sms_opt_outs_on_phone_e164"
  end

  create_table "sms_segments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.text "description"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.json "segment_rules", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "name"], name: "index_sms_segments_on_customer_id_and_name"
    t.index ["customer_id"], name: "index_sms_segments_on_customer_id"
  end

  create_table "sms_templates", force: :cascade do |t|
    t.text "body_template"
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.json "provider_template_codes", default: {}, null: false
    t.string "purpose", default: "transactional", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.json "variables", default: [], null: false
    t.index ["key"], name: "index_sms_templates_on_key", unique: true
  end

  create_table "speech_to_text_clips", force: :cascade do |t|
    t.integer "conversation_id"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "destination", default: "field", null: false
    t.string "error_code"
    t.string "field_dom_id", null: false
    t.string "language"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["conversation_id"], name: "index_speech_to_text_clips_on_conversation_id"
    t.index ["customer_id", "created_at"], name: "index_speech_to_text_clips_on_customer_id_and_created_at"
    t.index ["customer_id"], name: "index_speech_to_text_clips_on_customer_id"
    t.index ["status", "updated_at"], name: "index_speech_to_text_clips_on_status_and_updated_at"
  end

  create_table "support_ticket_messages", force: :cascade do |t|
    t.string "author_role", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.bigint "support_ticket_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["customer_id"], name: "index_support_ticket_messages_on_customer_id"
    t.index ["support_ticket_id"], name: "index_support_ticket_messages_on_support_ticket_id"
  end

  create_table "support_ticket_reads", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.datetime "last_read_at", null: false
    t.bigint "support_ticket_id", null: false
    t.bigint "user_id", null: false
    t.index ["customer_id"], name: "index_support_ticket_reads_on_customer_id"
    t.index ["user_id", "support_ticket_id"], name: "idx_support_ticket_reads_unique", unique: true
  end

  create_table "support_tickets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "last_message_at", null: false
    t.string "status", default: "open", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["customer_id"], name: "index_support_tickets_on_customer_id"
    t.index ["status", "last_message_at"], name: "index_support_tickets_on_status_and_last_message_at"
    t.index ["user_id"], name: "index_support_tickets_on_user_id"
  end

  create_table "trusted_devices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "expires_at", null: false
    t.string "ip"
    t.datetime "last_used_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["customer_id"], name: "index_trusted_devices_on_customer_id"
    t.index ["expires_at"], name: "index_trusted_devices_on_expires_at"
    t.index ["token_digest"], name: "index_trusted_devices_on_token_digest", unique: true
    t.index ["user_id"], name: "index_trusted_devices_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.integer "customer_id", null: false
    t.string "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "last_otp_at"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale"
    t.datetime "locked_at"
    t.boolean "otp_required_for_login", default: false, null: false
    t.string "otp_secret"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "sign_in_token"
    t.datetime "sign_in_token_sent_at"
    t.integer "status", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index "LOWER(email)", name: "index_users_on_lower_email", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["customer_id"], name: "index_users_on_customer_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["sign_in_token"], name: "index_users_on_sign_in_token", unique: true
    t.index ["status"], name: "index_users_on_status"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "users_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "website_layouts", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.json "sections", default: [], null: false
    t.string "theme_key"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_website_layouts_on_key", unique: true
  end

  create_table "website_pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.boolean "home", default: false, null: false
    t.string "layout_key"
    t.boolean "nav_visible", default: true, null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.json "sections", default: [], null: false
    t.string "slug", default: "", null: false
    t.string "theme_key"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "website_id", null: false
    t.index ["customer_id"], name: "index_website_pages_on_customer_id"
    t.index ["layout_key"], name: "index_website_pages_on_layout_key"
    t.index ["website_id", "slug"], name: "index_website_pages_on_website_id_and_slug", unique: true
    t.index ["website_id"], name: "index_website_pages_on_website_id"
    t.index ["website_id"], name: "index_website_pages_one_home", unique: true, where: "home = 1"
  end

  create_table "website_skeletons", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.string "name", null: false
    t.json "pages", default: [], null: false
    t.integer "position", default: 0, null: false
    t.string "theme_key"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_website_skeletons_on_key", unique: true
  end

  create_table "websites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.string "default_layout_key"
    t.json "footer", default: {}, null: false
    t.string "name", null: false
    t.boolean "published", default: false, null: false
    t.json "seo", default: {}, null: false
    t.string "skeleton_key", default: "presence", null: false
    t.string "tagline"
    t.json "theme", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_websites_on_customer_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_assistant_subsystem_builds", "ai_assistant_conversations", column: "conversation_id", on_delete: :cascade
  add_foreign_key "ai_assistant_subsystem_builds", "users", on_delete: :cascade
  add_foreign_key "billing_collection_attempts", "billing_invoices", on_delete: :restrict
  add_foreign_key "billing_collection_attempts", "billing_payment_methods", on_delete: :restrict
  add_foreign_key "billing_collection_attempts", "customers", on_delete: :restrict
  add_foreign_key "billing_collection_attempts", "payment_merchant_accounts", column: "merchant_account_id", on_delete: :restrict
  add_foreign_key "billing_collection_attempts", "payments", on_delete: :restrict
  add_foreign_key "billing_coupon_redemptions", "billing_coupons", on_delete: :restrict
  add_foreign_key "billing_coupon_redemptions", "billing_subscriptions", on_delete: :restrict
  add_foreign_key "billing_coupon_redemptions", "customers", on_delete: :restrict
  add_foreign_key "billing_invoice_line_items", "billing_invoices", on_delete: :restrict
  add_foreign_key "billing_invoice_line_items", "customers", on_delete: :restrict
  add_foreign_key "billing_invoice_sequences", "customers", on_delete: :restrict
  add_foreign_key "billing_invoices", "billing_coupon_redemptions", on_delete: :restrict
  add_foreign_key "billing_invoices", "billing_coupons", on_delete: :restrict
  add_foreign_key "billing_invoices", "billing_plan_changes", on_delete: :restrict
  add_foreign_key "billing_invoices", "billing_subscriptions", on_delete: :restrict
  add_foreign_key "billing_invoices", "customers", on_delete: :restrict
  add_foreign_key "billing_invoices", "payments", on_delete: :restrict
  add_foreign_key "billing_invoices", "users", column: "collection_override_by_id", on_delete: :restrict
  add_foreign_key "billing_invoices", "users", column: "settled_by_id", on_delete: :restrict
  add_foreign_key "billing_notices", "billing_collection_attempts", on_delete: :restrict
  add_foreign_key "billing_notices", "billing_invoices", on_delete: :restrict
  add_foreign_key "billing_notices", "billing_subscriptions", on_delete: :restrict
  add_foreign_key "billing_notices", "customers", on_delete: :restrict
  add_foreign_key "billing_payment_methods", "customers", on_delete: :restrict
  add_foreign_key "billing_payment_methods", "payment_merchant_accounts", column: "merchant_account_id", on_delete: :restrict
  add_foreign_key "billing_payment_methods", "payment_subscriptions", column: "payments_subscription_id", on_delete: :restrict
  add_foreign_key "billing_payment_methods", "users", column: "authorized_by_id", on_delete: :restrict
  add_foreign_key "billing_plan_changes", "billing_plans", column: "from_plan_id", on_delete: :restrict
  add_foreign_key "billing_plan_changes", "billing_plans", column: "to_plan_id", on_delete: :restrict
  add_foreign_key "billing_plan_changes", "billing_subscriptions", on_delete: :restrict
  add_foreign_key "billing_plan_changes", "customers", on_delete: :restrict
  add_foreign_key "billing_plan_limits", "billing_plans"
  add_foreign_key "billing_subscriptions", "billing_coupons", on_delete: :restrict
  add_foreign_key "billing_subscriptions", "billing_plans", on_delete: :restrict
  add_foreign_key "billing_subscriptions", "customers", on_delete: :restrict
  add_foreign_key "customer_feature_modules", "customers"
  add_foreign_key "customer_feature_modules", "feature_modules"
  add_foreign_key "email_backend_receipts", "email_credentials", column: "credential_id"
  add_foreign_key "email_list_memberships", "email_lists"
  add_foreign_key "email_list_memberships", "users"
  add_foreign_key "email_send_activity_lists", "email_lists"
  add_foreign_key "email_send_activity_lists", "email_send_activities"
  add_foreign_key "email_template_versions", "email_template_contents", column: "content_id"
  add_foreign_key "email_template_versions", "email_template_versions", column: "based_on_version_id", on_delete: :nullify
  add_foreign_key "email_template_versions", "email_templates"
  add_foreign_key "email_templates", "email_template_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "entities", "customers"
  add_foreign_key "entities", "entity_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "entity_domain_memberships", "customers"
  add_foreign_key "entity_domain_memberships", "entities", on_delete: :cascade
  add_foreign_key "entity_domain_memberships", "entity_domains", on_delete: :cascade
  add_foreign_key "entity_domains", "customers"
  add_foreign_key "entity_entries", "customers"
  add_foreign_key "entity_entries", "entities"
  add_foreign_key "entity_entries", "users", on_delete: :nullify
  add_foreign_key "entity_index_settings", "customers"
  add_foreign_key "entity_index_settings", "entities"
  add_foreign_key "feature_module_logs", "customers"
  add_foreign_key "feature_module_logs", "entity_entries"
  add_foreign_key "feature_module_logs", "feature_modules"
  add_foreign_key "flowchart_versions", "flowchart_versions", column: "based_on_version_id", on_delete: :nullify
  add_foreign_key "flowchart_versions", "flowcharts"
  add_foreign_key "flowcharts", "customers"
  add_foreign_key "flowcharts", "flowchart_versions", column: "current_version_id"
  add_foreign_key "flowcharts", "flowchart_versions", column: "launched_version_id"
  add_foreign_key "journey_runs", "customers", on_delete: :cascade
  add_foreign_key "journey_runs", "journeys", on_delete: :cascade
  add_foreign_key "journey_runs", "users", on_delete: :cascade
  add_foreign_key "journeys", "customers", on_delete: :cascade
  add_foreign_key "journeys", "entity_domains", on_delete: :cascade
  add_foreign_key "member_surface_settings", "customers"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "operation_invocations", "customers"
  add_foreign_key "operation_invocations", "users"
  add_foreign_key "operation_invocations", "users", column: "confirmed_by_id"
  add_foreign_key "page_shortcuts", "customers", on_delete: :cascade
  add_foreign_key "page_versions", "page_versions", column: "based_on_version_id", on_delete: :nullify
  add_foreign_key "page_versions", "pages"
  add_foreign_key "pages", "customers"
  add_foreign_key "pages", "entity_versions", on_delete: :nullify
  add_foreign_key "pages", "flowcharts", on_delete: :nullify
  add_foreign_key "pages", "page_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "payment_merchant_accounts", "customers"
  add_foreign_key "payment_methods", "customers", column: "billing_customer_id", on_delete: :restrict
  add_foreign_key "payment_methods", "users", column: "billing_authorized_by_id", on_delete: :restrict
  add_foreign_key "payment_orders", "customers"
  add_foreign_key "payment_reconciliation_bills", "customers"
  add_foreign_key "payment_refunds", "customers"
  add_foreign_key "payment_refunds", "payments"
  add_foreign_key "payment_subscriptions", "customers"
  add_foreign_key "payment_subscriptions", "payment_methods"
  add_foreign_key "payments", "customers"
  add_foreign_key "payments", "payment_orders"
  add_foreign_key "payments", "users"
  add_foreign_key "people_pending_claims", "customers"
  add_foreign_key "people_pending_claims", "entity_entries", on_delete: :nullify
  add_foreign_key "people_pending_claims", "users", on_delete: :cascade
  add_foreign_key "platform_announcement_dismissals", "customers", on_delete: :cascade
  add_foreign_key "platform_announcement_dismissals", "platform_announcements", on_delete: :cascade
  add_foreign_key "platform_announcement_dismissals", "users", on_delete: :cascade
  add_foreign_key "platform_announcement_reads", "customers", on_delete: :cascade
  add_foreign_key "platform_announcement_reads", "platform_announcements", on_delete: :cascade
  add_foreign_key "platform_announcement_reads", "users", on_delete: :cascade
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "roles", "customers"
  add_foreign_key "sms_backend_receipts", "sms_credentials", column: "credential_id"
  add_foreign_key "sms_campaign_recipients", "customers"
  add_foreign_key "sms_campaign_recipients", "sms_campaigns", column: "campaign_id"
  add_foreign_key "sms_campaign_recipients", "sms_contacts", column: "contact_id"
  add_foreign_key "sms_campaign_recipients", "sms_messages", column: "message_id"
  add_foreign_key "sms_campaigns", "customers"
  add_foreign_key "sms_campaigns", "sms_segments", column: "segment_id", on_delete: :nullify
  add_foreign_key "sms_campaigns", "sms_templates", column: "template_id"
  add_foreign_key "sms_campaigns", "users", column: "created_by_id"
  add_foreign_key "sms_campaigns", "users", column: "launched_by_id"
  add_foreign_key "sms_consent_events", "customers"
  add_foreign_key "sms_consent_events", "sms_contacts", column: "contact_id"
  add_foreign_key "sms_consent_events", "users", column: "actor_user_id"
  add_foreign_key "sms_contacts", "customers"
  add_foreign_key "sms_contacts", "entities", column: "source_entity_id", on_delete: :nullify
  add_foreign_key "sms_contacts", "entity_entries", column: "source_entry_id", on_delete: :nullify
  add_foreign_key "sms_messages", "customers"
  add_foreign_key "sms_messages", "sms_campaigns", column: "campaign_id"
  add_foreign_key "sms_messages", "sms_contacts", column: "contact_id"
  add_foreign_key "sms_messages", "sms_templates"
  add_foreign_key "sms_segments", "customers"
  add_foreign_key "speech_to_text_clips", "ai_assistant_conversations", column: "conversation_id", on_delete: :nullify
  add_foreign_key "support_ticket_messages", "customers", on_delete: :cascade
  add_foreign_key "support_ticket_messages", "support_tickets", on_delete: :cascade
  add_foreign_key "support_ticket_messages", "users", on_delete: :cascade
  add_foreign_key "support_ticket_reads", "customers", on_delete: :cascade
  add_foreign_key "support_ticket_reads", "support_tickets", on_delete: :cascade
  add_foreign_key "support_ticket_reads", "users", on_delete: :cascade
  add_foreign_key "support_tickets", "customers", on_delete: :cascade
  add_foreign_key "support_tickets", "users", on_delete: :cascade
  add_foreign_key "users", "customers"
  add_foreign_key "users_roles", "roles"
  add_foreign_key "users_roles", "users"
end
