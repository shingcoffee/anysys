# frozen_string_literal: true

module FeatureModules
  class CustomerAssignment < ApplicationRecord
    self.table_name = "customer_feature_modules"

    include TenantScoped
    include JsonSerializable

    json_attribute :configuration, default: {}

    enum :status, { active: 0, suspended: 1 }, default: :active

    belongs_to :feature_module, class_name: "FeatureModules::Module",
                                foreign_key: :feature_module_id
    belongs_to :customer

    validates :feature_module_id, uniqueness: { scope: :customer_id }

    scope :enabled, -> { where(status: :active) }

    delegate :key, :name, to: :feature_module, prefix: true

    def configured?(key)
      configuration_json&.dig(key.to_s).present?
    end

    # Merge keys onto the persisted JSON blob under a row lock so concurrent
    # settings surfaces (sign-up toggle, forgot-password toggle, module config)
    # cannot clobber each other's keys.
    def merge_configuration!(updates)
      with_lock do
        config = configuration_json || {}
        update!(configuration: config.merge(updates.stringify_keys).to_json)
      end
    end
  end
end
