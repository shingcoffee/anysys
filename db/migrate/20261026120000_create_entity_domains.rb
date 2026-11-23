# frozen_string_literal: true

class CreateEntityDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_domains do |t|
      t.references :customer, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.text :description
      t.string :color, null: false, default: "slate"
      t.timestamps null: false
    end

    add_index :entity_domains, "customer_id, LOWER(name)", unique: true, name: "idx_entity_domains_customer_name"

    # Membership is a per-customer row so a shared entity (customer_id NULL)
    # can be grouped by each tenant without touching the global row.
    create_table :entity_domain_memberships do |t|
      t.references :customer, null: false, foreign_key: true, index: false
      t.references :entity_domain, null: false, foreign_key: { on_delete: :cascade }
      t.references :entity, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps null: false
    end

    add_index :entity_domain_memberships, %i[customer_id entity_id], unique: true,
              name: "idx_entity_domain_memberships_customer_entity"
  end
end
