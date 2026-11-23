# frozen_string_literal: true

class AddFailPolicyAndScoreThresholdToCaptchaProviderSettings < ActiveRecord::Migration[8.1]
  def change
    # fail_policy: "open" (availability-first — vendor outages don't block the
    # user) or "closed" (security-first — a non-success blocks). Per-provider
    # default; per-action override lives in the protection concern.
    add_column :captcha_provider_settings, :fail_policy, :string, null: false, default: "open"

    # Score threshold for score-based providers (reCAPTCHA v3 etc.). NULL means
    # the provider is binary pass/fail (Aliyun, Turnstile).
    add_column :captcha_provider_settings, :score_threshold, :decimal, precision: 4, scale: 3

    # At most one provider may be the active one platform-wide.
    add_index :captcha_provider_settings, :enabled, unique: true, where: "enabled",
              name: "index_captcha_provider_settings_single_active"
  end
end
