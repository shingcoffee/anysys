# frozen_string_literal: true

class DropCaptchaVerifications < ActiveRecord::Migration[8.1]
  def change
    drop_table :captcha_verifications, if_exists: true
  end
end
