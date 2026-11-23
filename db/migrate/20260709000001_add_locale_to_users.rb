# frozen_string_literal: true

# Per-user UI language preference. Nullable: nil means "follow the request
# fallback chain" (cookie -> Accept-Language -> default :en). Only ever holds
# a value in I18n.available_locales.
class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string
  end
end
