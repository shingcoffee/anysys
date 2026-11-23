# frozen_string_literal: true

class MenuRegistry
  URL_HELPERS = Rails.application.routes.url_helpers

  ITEMS = [
    MenuItem.new(key: :home,     label_key: "chrome.menu_bar.items.home",
                 path_proc: ->(c) { URL_HELPERS.admin_dashboard_path(c.id) },
                 sidebar_contributor: nil),
    MenuItem.new(key: :assistant, label_key: "chrome.menu_bar.items.assistant",
                  path_proc: ->(c) { URL_HELPERS.admin_assistant_path(c.id) },
                  sidebar_contributor: nil),
    MenuItem.new(key: :users, label_key: "chrome.menu_bar.items.users",
                 path_proc: ->(c) { URL_HELPERS.admin_modules_authentication_users_path(c.id) },
                 active_paths: [->(c) { URL_HELPERS.admin_modules_authentication_users_path(c.id) }],
                 feature_module_key: "authentication", permitted_by: :admin_or_owner?),
    MenuItem.new(key: :payments, label_key: "chrome.menu_bar.items.payments",
                 path_proc: ->(c) { URL_HELPERS.admin_modules_payments_transactions_path(c.id) },
                 active_paths: [->(c) { "/#{c.id}/admin/modules/payments" }],
                 feature_module_key: "payment", permitted_by: :admin_or_owner?),
    MenuItem.new(key: :communication, label_key: "chrome.menu_bar.items.communication",
                 active_paths: [->(c) { "/#{c.id}/admin/modules/emails" }, ->(c) { "/#{c.id}/admin/modules/sms" }],
                 permitted_by: :admin_or_owner?, children: [
                   MenuItem.new(key: :email, label_key: "chrome.menu_bar.items.email",
                                description_key: "chrome.menu_bar.descriptions.email",
                                path_proc: ->(c) { URL_HELPERS.admin_modules_emails_send_activities_path(c.id) },
                                active_paths: [->(c) { "/#{c.id}/admin/modules/emails" }],
                                feature_module_key: "email"),
                   MenuItem.new(key: :sms, label_key: "chrome.menu_bar.items.sms",
                                description_key: "chrome.menu_bar.descriptions.sms",
                                path_proc: ->(c) { URL_HELPERS.admin_modules_sms_campaigns_path(c.id) },
                                active_paths: [->(c) { "/#{c.id}/admin/modules/sms" }],
                                feature_module_key: "sms")
                 ]),
    MenuItem.new(key: :entities, label_key: "chrome.menu_bar.items.entities",
                 path_proc: ->(c) { URL_HELPERS.admin_domains_path(c.id) },
                 sidebar_contributor: EntitiesContributor),
    MenuItem.new(key: :website_pages, label_key: "chrome.menu_bar.items.website_pages",
                 path_proc: ->(c) { URL_HELPERS.admin_modules_website_root_path(c.id) },
                 active_paths: [->(c) { URL_HELPERS.admin_modules_website_root_path(c.id) }],
                 feature_module_key: "website"),
    MenuItem.new(key: :modules,  label_key: "chrome.menu_bar.items.modules",
                 path_proc: ->(c) { URL_HELPERS.admin_modules_path(c.id) },
                 sidebar_contributor: ModulesContributor),
    MenuItem.new(key: :settings, label_key: "chrome.menu_bar.items.settings",
                 path_proc: ->(c) { URL_HELPERS.admin_setting_path(c.id) },
                 sidebar_contributor: SettingsContributor),
    MenuItem.new(key: :maintenance, label_key: "chrome.menu_bar.items.maintenance",
                 path_proc: ->(c) { URL_HELPERS.admin_maintenance_path(c.id) },
                 permitted_by: :platform_owner?,
                 sidebar_contributor: MaintenanceContributor)
  ].freeze

  def self.for(user, customer: nil)
    return [] if user.nil?

    available = if customer && user.admin_or_owner?
      FeatureModules::Module.available_for_customer(customer.id).pluck(:key)
    else
      []
    end

    ITEMS.filter_map do |item|
      next unless item.permitted_for?(user)
      next if item.feature_module_key && !available.include?(item.feature_module_key)
      next item unless item.dropdown?

      children = item.children.select do |child|
        child.permitted_for?(user) && (child.feature_module_key.nil? || available.include?(child.feature_module_key))
      end
      item.dup.tap { |copy| copy.children = children } if children.any?
    end
  end

  def self.item(key)
    ITEMS.find { |i| i.key == key }
  end
end
