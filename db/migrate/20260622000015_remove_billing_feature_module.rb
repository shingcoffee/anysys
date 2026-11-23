# frozen_string_literal: true

class RemoveBillingFeatureModule < ActiveRecord::Migration[8.1]
  def up
    fm = FeatureModules::Module.find_by(key: "billing")
    return unless fm

    FeatureModules::CustomerAssignment.where(feature_module_id: fm.id).delete_all
    fm.destroy
  end

  def down
    # Intentionally not reversible — billing is no longer a feature module
  end
end
