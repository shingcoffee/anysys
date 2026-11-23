# frozen_string_literal: true

class SettingsContributor < SidebarContributor
  MENU_ITEM = :settings

  # Existing node IDs remain the permission catalog IDs; only presentation changes.
  ITEMS = {
    "settings.member" => [:members, :member_portal],
    "settings.authentication.sign_up" => [:authentication, :member_registration],
    "settings.authentication.forget_password" => [:authentication, :password_reset],
    "settings.authentication.user_role_assignments" => [:authentication, :user_access],
    "settings.authentication.roles" => [:authentication, :roles_permissions],
    "settings.modules.authentication" => [:authentication, :account_security],
    "settings.captcha.status" => [:captcha, :public_page_protection],
    "settings.website.site" => [:website, :website],
    "settings.ai_assistant.status" => [:ai_assistant, :ai_assistant],
    "settings.email.daily_cap" => [:email, :email_sending_limit],
    "settings.email.template_tokens" => [:email, :email_personalization],
    "settings.sms.daily_cap" => [:sms, :sms_sending_limit],
    "settings.payment.merchant_accounts" => [:payment, :payment_providers],
    "settings.subscription" => [:billing, :plan_subscription],
    "settings.payment_methods" => [:billing, :billing_payment_methods],
    "settings.invoices" => [:billing, :invoices]
  }.freeze

  # Generic module settings accept both registry keys and plural aliases. Match
  # only those exact entry aliases; deeper settings retain their specific leaf.
  ENTRY_ALIASES = {
    account_security: %w[/modules/authentication /modules/authentications],
    email_sending_limit: %w[/modules/email /modules/emails],
    sms_sending_limit: %w[/modules/sms],
    ai_assistant: %w[/modules/ai_assistants]
  }.freeze

  def self.search_text(node)
    group, item = ITEMS[node.key]
    group_label = if %i[members billing].include?(group)
      I18n.t("settings_navigation.groups.#{group}")
    elsif group
      I18n.t("feature_modules.#{group}.name", default: nil)
    end

    [node.label, node.description,
     group_label, (I18n.t("settings_navigation.synonyms.#{item}") if item)].compact.join(" ")
  end

  ICONS = {
    overview: "M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z",
    member: "M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z",
    subscription: "M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z",
    payment_methods: "M21 12a2.25 2.25 0 00-2.25-2.25H15a3 3 0 11-6 0H5.25A2.25 2.25 0 003 12m18 0v6a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 18v-6m18 0V9M3 12V9m18 0a2.25 2.25 0 00-2.25-2.25H5.25A2.25 2.25 0 003 9m18 0V6a2.25 2.25 0 00-2.25-2.25H5.25A2.25 2.25 0 003 6v3",
    invoices: "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"
  }.freeze

  SETTING_ICON = "M3 6h5m3 0h10M3 12h10m3 0h5M3 18h5m3 0h10M8 4v4m5 2v4m-5 2v4".freeze

  def contribute
    return [] if customer_id.blank?

    tree = SidebarTree.new
    [overview_node, member_node, *billing_leaves, *module_setting_nodes].each { |node| tree.add(node) }
    # Apply the same permission projection for direct catalog consumers and SidebarBuilder.
    permitted = PermissionFilter.apply(tree, context.current_user).nodes_for(MENU_ITEM)
    overview = permitted.find { |node| node.key == "settings.overview" }
    member = permitted.find { |node| node.key == "settings.member" }
    modules = permitted.select { |node| node.key.start_with?("settings.modules.") }
    billing = permitted.select { |node| ITEMS.dig(node.key, 0) == :billing }

    organization = [*(member ? [section_header(:members), *flatten(member)] : []),
                    *(billing.empty? ? [] : [section_header(:billing), *billing.flat_map { |node| flatten(node) }])]

    [overview,
     *module_categories(modules),
     *(organization.empty? ? [] : [category_node(:organization, I18n.t("settings_navigation.categories.organization")), *organization])].compact
  end

  private

  def module_categories(modules)
    FeatureModules::NavigationOrder.by_section(modules) { |node| node.key.delete_prefix("settings.modules.") }.flat_map do |section, nodes|
      [category_node(section, FeatureModules::NavigationOrder.section_label(section)),
       *nodes.flat_map { |node| [module_section_header(node), *flatten(node)] }]
    end
  end

  def category_node(key, label)
    SidebarNode.new(key: "settings.category.#{key}", label: label, menu_item: MENU_ITEM, category: true)
  end

  def overview_node
    leaf(
      :overview,
      "/#{customer_id}/admin/settings",
      ICONS[:overview],
      description: I18n.t("admin_settings.catalog.cards.overview")
    )
  end

  def member_node
    leaf(
      :member,
      "/#{customer_id}/admin/settings/member",
      ICONS[:member],
      description: I18n.t("admin_settings.catalog.cards.member")
    )
  end

  def billing_leaves
    [
      leaf(
        :subscription,
        "/#{customer_id}/admin/settings/billing/subscription",
        ICONS[:subscription],
        description: I18n.t("admin_settings.catalog.cards.subscription")
      ),
      leaf(
        :payment_methods,
        "/#{customer_id}/admin/settings/billing/payment_methods",
        ICONS[:payment_methods],
        description: I18n.t("admin_settings.catalog.cards.payment_methods")
      ),
      leaf(
        :invoices,
        "/#{customer_id}/admin/settings/billing/invoices",
        ICONS[:invoices],
        description: I18n.t("admin_settings.catalog.cards.invoices"),
        match_prefix: "/#{customer_id}/admin/settings/billing/invoices"
      )
    ]
  end

  def module_setting_nodes
    FeatureModules::NavigationOrder.sort(FeatureModules::Module.available_for_customer(customer_id).by_name).filter_map do |fm|
      settings = Array(fm.registration_class.sidebar_contributions(context)[:settings])
      schema   = fm.configuration_schema_json || {}
      next if settings.empty? && schema.empty? && !fm.handoff_enabled?

      build_module_node(fm, settings)
    end
  end

  def build_module_node(fm, settings_contributions)
    icon = module_icon(fm.key)
    description = module_description(fm)
    return_url = fm.handoff_enabled? ? [return_url_node(fm)] : []

    if settings_contributions.empty? && return_url.empty?
      SidebarNode.new(
        key: "settings.modules.#{fm.key}",
        label: fm.display_name,
        menu_item: MENU_ITEM,
        path: module_path(fm),
        icon: icon,
        description: description
      )
    else
      SidebarNode.new(
        key: "settings.modules.#{fm.key}",
        label: fm.display_name,
        menu_item: MENU_ITEM,
        icon: icon,
        description: description,
        children: settings_contributions.map { |c|
          c.to_sidebar_node(menu_item: MENU_ITEM, module_key: fm.key, customer_id: customer_id)
        } + (fm.key == "authentication" ? [account_security_node(fm)] : []) + return_url
      )
    end
  end

  def return_url_node(fm)
    SidebarNode.new(
      key: "settings.#{fm.key}.return_url",
      label: I18n.t("settings_modules.configuration.return_url"),
      menu_item: MENU_ITEM,
      path: "#{module_path(fm)}/return_url"
    )
  end

  def leaf(key, path, icon, description: nil, match_prefix: nil)
    SidebarNode.new(
      key: "settings.#{key}",
      label: I18n.t("chrome.sidebar.settings.#{key}"),
      menu_item: MENU_ITEM,
      path: path,
      icon: icon,
      description: description,
      match_prefix: match_prefix
    )
  end

  GROUP_ICONS = {
    members: "M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z",
    access_security: "M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z",
    website: "M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418",
    messages: "M8.625 12a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H8.25m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H12m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0h-.375M21 12c0 4.556-4.03 8.25-9 8.25a9.764 9.764 0 01-2.555-.337A5.972 5.972 0 015.41 20.97a5.969 5.969 0 01-.474-.065 4.48 4.48 0 00.978-2.025c.09-.457-.133-.901-.467-1.226C3.93 16.178 3 14.189 3 12c0-4.556 4.03-8.25 9-8.25s9 3.694 9 8.25z",
    payments: "M2.25 18.75a60.07 60.07 0 0115.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 013 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 00-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 01-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 003 15h-.75M15 10.5a3 3 0 11-6 0 3 3 0 016 0zm3 0h.008v.008H18V10.5zm-12 0h.008v.008H6V10.5z",
    billing: "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"
  }.freeze

  def section_header(key)
    SidebarNode.new(
      key: "settings.section.#{key}",
      label: I18n.t("settings_navigation.groups.#{key}"),
      menu_item: MENU_ITEM,
      icon: GROUP_ICONS[key],
      description: I18n.t("admin_settings.catalog.groups.#{key}"),
      section_root: true
    )
  end

  def module_section_header(node)
    SidebarNode.new(
      key: "settings.section.#{node.key.delete_prefix('settings.modules.')}",
      label: node.label,
      menu_item: MENU_ITEM,
      icon: node.icon,
      tone: node.key.delete_prefix("settings.modules."),
      description: node.description,
      section_root: true
    )
  end

  def module_path(fm)
    segment = fm.key == "authentication" ? fm.key : fm.key.pluralize
    "/#{customer_id}/admin/settings/modules/#{segment}"
  end

  def account_security_node(fm)
    SidebarNode.new(
      key: "settings.modules.authentication", label: fm.display_name,
      menu_item: MENU_ITEM, path: module_path(fm), icon: module_icon(fm.key),
      permitted_by: :admin_or_owner?
    )
  end

  def flatten(node, description: nil)
    # Filtering happens before flattening, so future nested contribution guards survive.
    description = node.description.presence || description
    [*(node.link? ? [decorate(node, description: description)] : []),
     *node.children.flat_map { |child| flatten(child, description: description) }]
  end

  def decorate(node, description:)
    item = ITEMS[node.key]&.last
    SidebarNode.new(
      key: node.key, label: item ? I18n.t("settings_navigation.items.#{item}") : node.label,
      menu_item: MENU_ITEM, path: node.path, icon: node.icon.presence || SETTING_ICON, badge: node.badge,
      permitted_by: node.permitted_by,
      description: item ? I18n.t("settings_navigation.descriptions.#{item}") : description,
      match_prefix: item == :account_security ? nil : (node.match_prefix || node.path),
      match_paths: node.match_paths + Array(ENTRY_ALIASES[item]).map { |suffix| "/#{customer_id}/admin/settings#{suffix}" }
    )
  end

  def module_icon(key)
    Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch(
      key.to_s,
      Admin::Maintenance::Platform::ModuleSettingsHelper::DEFAULT_MODULE_ICON_PATH
    )
  end

  def module_description(fm)
    fallback = I18n.t("admin_settings.catalog.modules.fallback", name: fm.display_name)
    I18n.t("admin_settings.catalog.modules.#{fm.key}", default: fallback)
  end
end
