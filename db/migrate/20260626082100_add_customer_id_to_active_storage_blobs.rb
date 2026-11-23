# frozen_string_literal: true

class AddCustomerIdToActiveStorageBlobs < ActiveRecord::Migration[8.1]
  def change
    add_column :active_storage_blobs, :customer_id, :integer
    add_index  :active_storage_blobs, :customer_id
  end
end
