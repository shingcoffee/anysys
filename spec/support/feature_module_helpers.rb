# frozen_string_literal: true

# Shared FeatureModules catalog + assignment helpers.
# Creating a Customer auto-provisions required modules (e.g. authentication)
# via after_create. Use these helpers instead of `create(:customer_feature_module, ...)`
# to avoid uniqueness violations.
module FeatureModuleHelpers
  def ensure_customer_feature_module(customer, feature_module, **attrs)
    cfm = FeatureModules::CustomerAssignment.find_or_initialize_by(
      customer: customer,
      feature_module: feature_module
    )
    cfm.assign_attributes(attrs)
    cfm.save!
    cfm
  end

  def find_or_create_feature_module!(key, name: nil)
    key = key.to_s
    fm = FeatureModules::Module.find_or_create_by!(key: key) do |record|
      record.name = name || key
      record.status = :active
    end
    updates = { status: :active }
    updates[:name] = name if name
    fm.update!(updates)
    fm
  end

  def enable_module!(key, customer, name: nil, **assignment_attrs)
    fm = find_or_create_feature_module!(key, name: name)
    ensure_customer_feature_module(customer, fm, status: :active, **assignment_attrs)
    fm
  end
end

RSpec.configure do |config|
  config.include FeatureModuleHelpers
end
