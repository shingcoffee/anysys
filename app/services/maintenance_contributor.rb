# frozen_string_literal: true

class MaintenanceContributor < SidebarContributor
  MENU_ITEM = :maintenance

  ICONS = {
    customer_profile: "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
    constants: "M7 20l4-16m2 16l4-16M6 9h14M4 15h14",
    modules: "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4",
    entities: "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4",
    flowcharts: "M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7m0 10a2 2 0 002 2h2a2 2 0 002-2V7a2 2 0 00-2-2h-2a2 2 0 00-2 2",
    pages: "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
    customers: "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
    users: "M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z",
    module_settings: "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z",
    billing: "M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z",
    industry_templates: "M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z",
    code_generators: "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
    developer_docs: "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253",
    announcements: "M11 5.882V19.24a1.76 1.76 0 01-3.417.592l-2.147-6.15M18 13a3 3 0 100-6M5.436 13.683A4.001 4.001 0 017 6h1.832c4.1 0 7.625-1.234 9.168-3v14c-1.543-1.766-5.067-3-9.168-3H7a3.988 3.988 0 01-1.564-.317z",
    support_tickets: "M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
    shared_resources: "M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z"
  }.freeze

  def contribute
    return [] if customer_id.blank?

    nodes = [
      leaf(:customer_profile, "/#{customer_id}/admin/maintenance/customer_profile", ICONS[:customer_profile]),
      leaf(:constants,        "/#{customer_id}/admin/maintenance/constants", ICONS[:constants]),
      leaf(:modules,          "/#{customer_id}/admin/maintenance/modules", ICONS[:modules]),
      leaf(:entities,         "/#{customer_id}/admin/maintenance/entities", ICONS[:entities])
    ]
    if FlowchartVisibility.allowed?(current_user)
      nodes << leaf(:flowcharts, "/#{customer_id}/admin/maintenance/flowcharts", ICONS[:flowcharts])
    end
    nodes << leaf(:pages, "/#{customer_id}/admin/maintenance/pages", ICONS[:pages])
    nodes << SidebarNode.new(key: "maintenance.page_shortcuts", label: I18n.t("page_shortcuts.title"),
                             menu_item: MENU_ITEM, path: "/#{customer_id}/admin/maintenance/page_shortcuts", icon: ICONS[:pages])

    # Platform items (only visible under platform owner customer 81721200)
    if customer_id.to_s == "81721200" && current_user&.platform_owner?
      nodes += [
        section_header(:platform),
        leaf(:customers,           "/#{customer_id}/admin/maintenance/platform/customers", ICONS[:customers]),
        leaf(:announcements,       "/#{customer_id}/admin/maintenance/platform/announcements", ICONS[:announcements]),
        leaf(:support_tickets,       "/#{customer_id}/admin/maintenance/platform/support_tickets", ICONS[:support_tickets]),
        leaf(:module_settings,     "/#{customer_id}/admin/maintenance/platform/module_settings", ICONS[:module_settings]),
        leaf(:billing,             "/#{customer_id}/admin/maintenance/platform/billing/plans", ICONS[:billing],
             match_prefix: "/#{customer_id}/admin/maintenance/platform/billing"),
        leaf(:industry_templates,  "/#{customer_id}/admin/maintenance/platform/industry_templates", ICONS[:industry_templates]),
        leaf(:code_generators,     "/#{customer_id}/admin/maintenance/platform/code_generators", ICONS[:code_generators]),
        leaf(:developer_docs,      "/#{customer_id}/admin/maintenance/platform/developer_docs", ICONS[:developer_docs],
             match_prefix: "/#{customer_id}/admin/maintenance/platform/developer_docs"),
        group(:shared_resources, ICONS[:shared_resources], [
          leaf(:shared_constants,  "/#{customer_id}/admin/maintenance/platform/constants", ICONS[:constants],
               match_prefix: "/#{customer_id}/admin/maintenance/platform/constants"),
          leaf(:shared_entities,   "/#{customer_id}/admin/maintenance/platform/entities", ICONS[:entities],
               match_prefix: "/#{customer_id}/admin/maintenance/platform/entities"),
          leaf(:shared_flowcharts, "/#{customer_id}/admin/maintenance/platform/flowcharts", ICONS[:flowcharts],
               match_prefix: "/#{customer_id}/admin/maintenance/platform/flowcharts"),
          leaf(:shared_pages,      "/#{customer_id}/admin/maintenance/platform/pages", ICONS[:pages],
               match_prefix: "/#{customer_id}/admin/maintenance/platform/pages")
        ])
      ]
    end

    nodes
  end

  private

  # +key+ is a stable symbol used both for the node key (active-state matching)
  # and to look up the request-localized label.
  def leaf(key, path, icon = nil, match_prefix: nil)
    SidebarNode.new(key: "maintenance.#{key}", label: I18n.t("chrome.sidebar.maintenance.#{key}"),
                    menu_item: MENU_ITEM, path: path, icon: icon, match_prefix: match_prefix || path)
  end

  def section_header(key)
    SidebarNode.new(
      key: "maintenance.section.#{key}",
      label: I18n.t("chrome.sidebar.maintenance.#{key}"),
      menu_item: MENU_ITEM,
      section_root: true
    )
  end

  def group(key, icon, children)
    SidebarNode.new(
      key: "maintenance.#{key}",
      label: I18n.t("chrome.sidebar.maintenance.#{key}"),
      menu_item: MENU_ITEM,
      icon: icon,
      children: children
    )
  end
end
