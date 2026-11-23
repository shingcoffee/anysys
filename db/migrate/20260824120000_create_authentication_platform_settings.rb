# frozen_string_literal: true

class CreateAuthenticationPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :authentication_platform_settings do |t|
      t.boolean :allow_customer_signup, null: false, default: true
      t.timestamps
    end
  end
end
