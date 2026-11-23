# frozen_string_literal: true

class AddSkippedToCaptchaUrlThrottles < ActiveRecord::Migration[8.1]
  def change
    add_column :captcha_url_throttles, :skipped, :boolean, null: false, default: false
  end
end
