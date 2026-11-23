# frozen_string_literal: true

# Removes the orphaned "Test" feature module — a leftover dev row that surfaces
# on /:cid/admin/maintenance/platform/module_settings with no purpose. It has
# no backing registration under app/services/feature_modules/, and
# FeatureModules::BaseModule.register! only ever creates/updates module rows,
# never prunes them, so an obsolete module lingers until explicitly deleted.
#
# Mirrors RemoveBillingFeatureModule. Matches by key OR display name so it works
# regardless of how the stale row was originally keyed, and guards against ever
# deleting a module that still has code backing it.
class RemoveTestFeatureModule < ActiveRecord::Migration[8.1]
  def up
    scope = FeatureModules::Module.where(key: "test")
                                  .or(FeatureModules::Module.where(name: "Test"))

    scope.find_each do |fm|
      next if registration_file_exists?(fm.key)

      FeatureModules::CustomerAssignment.where(feature_module_id: fm.id).delete_all
      FeatureModules::Log.where(feature_module_id: fm.id).delete_all
      fm.destroy
    end
  end

  def down
    # Intentionally not reversible — "Test" was never a real feature module.
  end

  private

  def registration_file_exists?(key)
    Rails.root.join("app/services/feature_modules", key.to_s, "registration.rb").exist?
  end
end
