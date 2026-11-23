# frozen_string_literal: true

module AccessPoints
  class ModuleProvider < Provider
    def group_key   = "modules"
    def group_label = I18n.t("admin_settings.access_points.groups.modules")

    def call(customer_id:)
      @group_labels = {}
      FeatureModules::Module
        .available_for_customer(customer_id)
        .map { |fm| descriptor_for(fm) }
    end

    def label_for_group(key)
      @group_labels&.[](key) || super
    end

    private

    def descriptor_for(fm)
      derived_key = "modules.#{fm.key}"
      @group_labels[derived_key] = fm.display_name
      Descriptor.new(
        subject_type: "Module",
        subject_key:  fm.key,
        subject_id:   nil,
        actions:      [:manage],
        group_key:    derived_key,
        label:        fm.display_name,
        description:  fm.respond_to?(:description) ? fm.description : nil
      )
    end
  end
end
