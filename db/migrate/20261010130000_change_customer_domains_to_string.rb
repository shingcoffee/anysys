# frozen_string_literal: true

require "json"

class ChangeCustomerDomainsToString < ActiveRecord::Migration[8.1]
  def up
    add_column :customers, :domain, :string, limit: 253

    if column_exists?(:customers, :domains)
      select_all("SELECT id, domains FROM customers").each do |row|
        list = JSON.parse(row["domains"].presence || "[]")
        name = Array(list).find(&:present?)
        next if name.blank?

        execute("UPDATE customers SET domain = #{quote(name)} WHERE id = #{Integer(row["id"])}")
      end
      remove_column :customers, :domains
    end

    add_index :customers, :domain, unique: true
  end

  def down
    add_column :customers, :domains, :json, null: false, default: []
    select_all("SELECT id, domain FROM customers WHERE domain IS NOT NULL").each do |row|
      execute("UPDATE customers SET domains = #{quote([row["domain"]].to_json)} WHERE id = #{Integer(row["id"])}")
    end
    remove_index :customers, :domain
    remove_column :customers, :domain
  end
end
