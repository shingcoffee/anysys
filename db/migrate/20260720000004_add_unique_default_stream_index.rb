# frozen_string_literal: true

class AddUniqueDefaultStreamIndex < ActiveRecord::Migration[8.1]
  def up
    add_index :email_streams, %i[customer_id kind],
              unique: true,
              where: "default_for_kind = TRUE AND status = 'active'",
              name:   "index_email_streams_on_customer_id_and_kind_unique_default"
  end

  def down
    remove_index :email_streams, name: "index_email_streams_on_customer_id_and_kind_unique_default"
  end
end
