# frozen_string_literal: true

class SeedDefaultEmailStreams < ActiveRecord::Migration[8.1]
  def up
    Customer.find_each do |customer|
      Emails::Streams::ProvisionDefaults.call(customer)
    end
  end

  def down
    Emails::Stream.where(key: %w[transactional marketing automated]).destroy_all
  end
end
