class RemoveExtensibilityAndStepActions < ActiveRecord::Migration[8.1]
  def up
    drop_table :payments if table_exists?(:payments)
    drop_table :extended_model_entries if table_exists?(:extended_model_entries)
    drop_table :base_model_configurations if table_exists?(:base_model_configurations)
    remove_column :entities, :extendable_models if column_exists?(:entities, :extendable_models)
    remove_column :feature_modules, :step_actions if column_exists?(:feature_modules, :step_actions)
    remove_column :feature_modules, :base_model_settings if column_exists?(:feature_modules, :base_model_settings)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
