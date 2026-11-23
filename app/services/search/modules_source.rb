# frozen_string_literal: true

module Search
  class ModulesSource < BaseSource
    protected

    def group_key   = :modules
    def group_label = I18n.t("chrome.inline_search.groups.modules")

    def items
      FeatureModules::Module
        .enabled_for_customer(customer.id)
        .where("LOWER(feature_modules.name) LIKE ? ESCAPE '\\'", "%#{escaped_like.downcase}%")
        .order(:name)
        .limit(MAX_PER_GROUP)
        .map { |fm|
          {
            label: fm.display_name,
            path:  path_for(fm),
            type:  :module
          }
        }
    end

    private

    # Prefer the module's declared admin entry path. Non-admin entry paths
    # (e.g. public checkout / sign-in) fall back to the customer settings page
    # so search always lands in an admin-usable surface.
    def path_for(fm)
      entry = fm.registration_class.entry_path_for(customer)
      return entry if entry.present? && entry.include?("/admin/")

      "/#{customer.id}/admin/settings/modules/#{fm.key.pluralize}"
    end
  end
end
