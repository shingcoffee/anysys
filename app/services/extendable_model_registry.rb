# frozen_string_literal: true

# Collects, across all feature modules enabled for a customer, the models the
# platform owner has flagged as extendable. Used to populate the Entity Builder's
# "extend base model" picker so it only ever offers owner-approved models.
class ExtendableModelRegistry
  def self.for_customer(customer_id)
    new(customer_id).call
  end

  # Attribute names the owner has checked for this extended model. None are
  # selected until they are checked.
  def self.selected_attributes(customer_id, class_name)
    return [] if customer_id.blank?

    FeatureModules::Module.enabled_for_customer(customer_id)
                          .select { |mod| mod.extendable_model?(class_name) }
                          .flat_map { |mod| mod.extendable_attributes_for(class_name) }
                          .uniq
  end

  def initialize(customer_id)
    @customer_id = customer_id
  end

  def call
    return [] if @customer_id.blank?

    FeatureModules::Module.enabled_for_customer(@customer_id).flat_map do |mod|
      Array(mod.extendable_models_json).map do |class_name|
        { class_name: class_name, label: class_name.demodulize, module_key: mod.key }
      end
    end
  end
end
