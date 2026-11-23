class AddContractToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :contract, :text
  end
end
