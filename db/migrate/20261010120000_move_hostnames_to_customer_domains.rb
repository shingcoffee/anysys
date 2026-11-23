# frozen_string_literal: true

class MoveHostnamesToCustomerDomains < ActiveRecord::Migration[8.1]
  def up
    add_column :customers, :domains, :json, null: false, default: []

    if table_exists?(:customer_hostnames)
      rows = select_all("SELECT customer_id, hostname FROM customer_hostnames ORDER BY hostname, id")
      rows.group_by { |row| row["customer_id"] }.each do |customer_id, items|
        domains = items.map { |item| item["hostname"].to_s }.uniq.sort
        execute("UPDATE customers SET domains = #{quote(domains.to_json)} WHERE id = #{Integer(customer_id)}")
      end
      drop_table :customer_hostnames
    end
  end

  def down
    create_table :customer_hostnames do |t|
      t.references :customer, type: :bigint, null: false, foreign_key: { on_delete: :cascade }
      t.string :hostname, null: false, limit: 253
      t.timestamps
    end
    add_index :customer_hostnames, :hostname, unique: true

    Customer.reset_column_information
    Customer.unscoped.find_each do |customer|
      Array(customer.domains).each do |domain|
        execute(<<~SQL.squish)
          INSERT INTO customer_hostnames (customer_id, hostname, created_at, updated_at)
          VALUES (#{Integer(customer.id)}, #{quote(domain)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end
    remove_column :customers, :domains
  end
end
