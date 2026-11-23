# frozen_string_literal: true

class RequireJourneyDomain < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM journeys WHERE entity_domain_id IS NULL"
    remove_foreign_key :journeys, :entity_domains
    change_column_null :journeys, :entity_domain_id, false
    add_foreign_key :journeys, :entity_domains, on_delete: :cascade
  end

  def down
    remove_foreign_key :journeys, :entity_domains
    change_column_null :journeys, :entity_domain_id, true
    add_foreign_key :journeys, :entity_domains, on_delete: :nullify
  end
end
