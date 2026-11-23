# frozen_string_literal: true

# Tenant-level (customer-wide) default UI locale, selectable by the platform
# owner when provisioning a customer. Nullable: nil means "no tenant default"
# — the request falls through to Accept-Language / :en. When present it is a
# fallback beneath each user's own choice (params/user pref/cookie), applied
# only when the user has expressed none. Sits above Accept-Language so a fresh
# user lands in the tenant's language. Only ever holds a value in
# I18n.available_locales.
class AddLocaleToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :locale, :string
  end
end
