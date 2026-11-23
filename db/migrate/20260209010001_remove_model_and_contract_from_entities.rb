# frozen_string_literal: true

class RemoveModelAndContractFromEntities < ActiveRecord::Migration[8.1]
  def change
    remove_column :entities, :model, :text
    remove_column :entities, :contract, :text
  end
end
