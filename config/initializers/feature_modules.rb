# frozen_string_literal: true

# Auto-discover and register every feature module under app/services/feature_modules/*/registration.rb.
#
# To add a new feature module:
#   1. Create app/services/feature_modules/<key>/registration.rb extending FeatureModules::BaseModule
#   2. (Optional) If it should be required for all customers, call `required!` in the registration class
#   3. That's it — no edits to this file.
#
Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?(:feature_modules)

  registration_paths = Rails.root.glob("app/services/feature_modules/*/registration.rb")

  registration_paths.each do |path|
    require_dependency(path.to_s)

    # Derive module name from directory: .../feature_modules/<key>/registration.rb
    key_dir = path.parent.basename.to_s
    klass_name = "FeatureModules::#{key_dir.camelize}::Registration"

    begin
      klass = klass_name.constantize
    rescue NameError => e
      AppLogger.warn("Skipping feature module at #{path}: #{e.message}", source: "FeatureModules")
      next
    end

    klass.register!
  end

  # Ensure required modules are provisioned for all existing customers
  ::FeatureModules::Module.required.find_each do |fm|
    Customer.find_each do |customer|
      cfm = FeatureModules::CustomerAssignment.find_or_initialize_by(customer: customer, feature_module: fm)
      next if cfm.persisted? && cfm.active?

      cfm.update!(
        status: :active,
        enabled_at: cfm.enabled_at || Time.current,
        configuration: cfm.configuration.presence || {}.to_json
      )
      fm.registration_class.provision!(customer)
    end
  end
rescue ActiveRecord::StatementInvalid, ActiveModel::UnknownAttributeError => e
  AppLogger.warn("Feature module registration skipped: #{e.message}", source: "FeatureModules")
end
