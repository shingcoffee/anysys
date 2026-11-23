# frozen_string_literal: true

module Captcha
  # One row per captcha vendor holding platform-wide credentials and tunables.
  # Vendor-specific fields live in the JSON `config` blob; only the credential
  # pair (`access_key_id` / `access_key_secret`), `enabled`, `fail_policy` and
  # `score_threshold` are typed columns shared by every vendor.
  #
  # `enabled` is the real platform-wide switch AND the active-provider selector:
  # at most one row may be enabled (partial unique index), and `.active` returns
  # that row when it is fully configured. Adding a new vendor is still a matter
  # of registering a Captcha::Providers::* subclass — no schema change.
  class ProviderSettings < ApplicationRecord
    include JsonSerializable

    self.table_name = "captcha_provider_settings"

    FAIL_POLICIES = %w[open closed].freeze

    encrypts :access_key_secret
    json_attribute :config, default: {}

    validates :provider, presence: true, uniqueness: true,
                         inclusion: { in: ->(_) { Captcha::Providers.keys.map(&:to_s) } }
    validates :fail_policy, inclusion: { in: FAIL_POLICIES }
    validates :score_threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
                                allow_nil: true

    # The single active provider row — enabled AND fully configured. Returns nil
    # when no provider is enabled or the enabled one is not yet configured, in
    # which case the verify activity degrades to :disabled (fail-open, since the
    # widget never renders and no token arrives).
    def self.active
      row = where(enabled: true).first
      row if row&.configured?
    end

    # Fetch (or lazily create) the row for an explicit provider key. Used by the
    # platform settings UI and the provisioner. Race-safe: a concurrent first
    # insert (unique provider index) is retried as a find.
    def self.for_provider(provider_key)
      key = provider_key.to_s
      find_or_create_by!(provider: key)
    rescue ActiveRecord::RecordNotUnique
      find_by!(provider: key)
    end

    def provider_class
      Captcha::Providers.for(provider)
    end

    # Vendor-agnostic readiness check. Defers the rule to the provider class so
    # each vendor requires its own fields. An unknown/stale provider key degrades
    # to "not configured" rather than raising into callers/views.
    def configured?
      provider_class.configured?(self)
    rescue ArgumentError
      false
    end

    def score_based?
      provider_class.score_based?
    rescue ArgumentError
      false
    end

    def fail_open?   = fail_policy.to_s != "closed"
    def fail_closed? = fail_policy.to_s == "closed"

    # Make this the single active provider, atomically clearing any other
    # enabled row so the partial-unique index is never violated. Two concurrent
    # "make active" submissions can momentarily both hold enabled=true against
    # the partial unique index; the loser retries once against the now-cleared
    # state rather than surfacing a 500.
    def activate!
      attempts = 0
      begin
        transaction do
          self.class.where.not(id: id).where(enabled: true).update_all(enabled: false)
          update!(enabled: true)
        end
      rescue ActiveRecord::RecordNotUnique
        raise if (attempts += 1) > 1

        retry
      end
    end

    def deactivate!
      update!(enabled: false)
    end

    # Read a JSON config key with a default.
    def config_value(key, default = nil)
      config_json.fetch(key.to_s, default)
    end

    def write_config(hash)
      self.config_json = config_json.merge(hash.transform_keys(&:to_s))
    end
  end
end
