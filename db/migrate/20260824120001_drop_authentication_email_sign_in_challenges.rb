# frozen_string_literal: true

class DropAuthenticationEmailSignInChallenges < ActiveRecord::Migration[8.1]
  def change
    drop_table :authentication_email_sign_in_challenges, if_exists: true
  end
end
