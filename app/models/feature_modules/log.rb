# frozen_string_literal: true

module FeatureModules
  class Log < ApplicationRecord
    self.table_name = "feature_module_logs"

    include TenantScoped
    include JsonSerializable

    json_attribute :request_data, default: {}
    json_attribute :response_data, default: {}

    enum :status, { success: 0, failure: 1 }, default: :success

    belongs_to :feature_module, class_name: "FeatureModules::Module",
                                foreign_key: :feature_module_id
    belongs_to :entity_entry, optional: true

    validates :action, presence: true

    scope :recent, -> { order(created_at: :desc) }
    scope :failures, -> { where(status: :failure) }
  end
end
