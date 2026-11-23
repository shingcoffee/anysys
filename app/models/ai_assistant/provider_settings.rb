# frozen_string_literal: true

module AiAssistant
  # One row per vendor holding platform-wide credentials and tunables.
  # Vendor-specific fields live in the JSON `config` blob; `api_key` plus the
  # two exclusive job flags are typed columns shared by every vendor.
  #
  # `transcribe_active` / `generation_active` are the real platform-wide
  # switches AND the per-job selectors: at most one row may hold each flag
  # (partial unique indexes). `.active_for(job)` returns that row when it is
  # fully configured. Adding a new vendor is still a matter of registering an
  # AiAssistant::Providers::* subclass — no schema change.
  class ProviderSettings < ApplicationRecord
    include JsonSerializable

    self.table_name = "ai_assistant_provider_settings"

    JOBS = [ :transcribe, :generation ].freeze

    encrypts :api_key
    json_attribute :config, default: {}

    validates :provider, presence: true, uniqueness: true,
                         inclusion: { in: ->(_) { AiAssistant::Providers.keys.map(&:to_s) } }

    # The active provider row for one job — flagged AND fully configured.
    # Returns nil when no provider holds that job or the assignee is not yet
    # configured, in which case enqueue / reply fail closed.
    def self.active_for(job)
      column = job_column(job)
      row = where(column => true).first
      row if row&.configured?
    end

    # Fetch (or lazily create) the row for an explicit provider key. Used by the
    # platform settings UI. Race-safe: a concurrent first insert (unique
    # provider index) is retried as a find.
    def self.for_provider(provider_key)
      key = provider_key.to_s
      find_or_create_by!(provider: key)
    rescue ActiveRecord::RecordNotUnique
      find_by!(provider: key)
    end

    def self.job_column(job)
      job = job.to_sym
      raise ArgumentError, "unknown AI Assistant job: #{job.inspect}" unless JOBS.include?(job)

      :"#{job}_active"
    end

    def provider_class
      AiAssistant::Providers.for(provider)
    end

    # Vendor-agnostic readiness check. Defers the rule to the provider class so
    # each vendor requires its own fields. An unknown/stale provider key degrades
    # to "not configured" rather than raising into callers/views.
    def configured?
      provider_class.configured?(self)
    rescue ArgumentError
      false
    end

    # Make this the single assignee for +job+, atomically clearing any other
    # row's flag so the partial-unique index is never violated. Two concurrent
    # "make active" submissions can momentarily both hold the flag against
    # the partial unique index; the loser retries once against the now-cleared
    # state rather than surfacing a 500.
    def activate_for!(job)
      column = self.class.job_column(job)
      attempts = 0
      begin
        transaction do
          self.class.where.not(id: id).where(column => true).update_all(column => false)
          update!(column => true)
        end
      rescue ActiveRecord::RecordNotUnique
        raise if (attempts += 1) > 1

        retry
      end
    end

    def deactivate_for!(job)
      update!(self.class.job_column(job) => false)
    end

    def config_value(key, default = nil)
      config_json.fetch(key.to_s, default)
    end

    def write_config(hash)
      self.config_json = config_json.merge(hash.transform_keys(&:to_s))
    end
  end
end
