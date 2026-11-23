# frozen_string_literal: true

class CustomerFormComponent < ApplicationComponent
  attr_reader :customer, :tenant_customer_id

  TIER_KEYS = Customer.tiers.keys
  # Endonyms reused from the language switcher so the option labels stay
  # locale-independent (a language is always shown in its own script).
  LOCALE_OPTIONS = LocaleSwitcherComponent::DISPLAY_NAMES.map { |code, name| [name, code.to_s] }

  def initialize(customer:, customer_id: nil)
    @customer = customer
    @tenant_customer_id = customer_id
  end

  # Get the current customer ID, preferring the passed parameter over the helper
  def current_customer_id
    @tenant_customer_id || helpers.current_customer_id
  end

  def form_url
    if customer.persisted?
      helpers.admin_maintenance_platform_customer_path(current_customer_id, customer)
    else
      helpers.admin_maintenance_platform_customers_path(current_customer_id)
    end
  end

  def cancel_url
    if customer.persisted?
      helpers.admin_maintenance_platform_customer_path(current_customer_id, customer)
    else
      helpers.admin_maintenance_platform_customers_path(current_customer_id)
    end
  end

  def form_method
    customer.persisted? ? :patch : :post
  end

  def submit_label
    customer.persisted? ? I18n.t("chrome.customer_form.update_customer") : I18n.t("chrome.customer_form.create_customer")
  end

  def tier_options
    TIER_KEYS.map { |tier| [I18n.t("chrome.customer_form.tiers.#{tier}"), tier] }
  end

  def industry_options
    Customer.grouped_industry_options
  end

  def locale_options
    LOCALE_OPTIONS
  end
end
