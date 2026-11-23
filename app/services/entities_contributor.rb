# frozen_string_literal: true

# Sidebar for the Domains menu: one node per domain (by name, tinted with the
# domain colour) listing its browsable entities as plain rows, primary first
# (EntityDomains::EntityOrder), with entities in no domain under a trailing
# "Other" node, which also stands alone when only unbound forms belong there.
# Each domain links to its page at /:cid/admin/domains/:key and opens while
# that page, its Forms list (or one of its entities) is shown; the first
# domain also answers the bare /:cid/admin/domains. Without any domain the
# entities are listed flat.
class EntitiesContributor < SidebarContributor
  MENU_ITEM = :entities

  ICONS = {
    all: "M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z",
    domain: "m12 2.75 9 5-9 5-9-5 9-5ZM3 12l9 5 9-5M3 16.25l9 5 9-5",
    ungrouped: "M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
  }.freeze

  def contribute
    return [] if customer_id.blank?

    entities = EntityAssociationGraph.build(customer_id).all_entities
    return [] if entities.empty?

    sections = EntityDomains::Layout.call(customer_id: customer_id, entities: entities)
                                    .reject { |section| section.items.empty? }
    return entity_nodes(entities) if sections.all?(&:ungrouped?)

    if sections.none?(&:ungrouped?) && unbound_forms?
      sections += [EntityDomains::Layout::Section.new(domain: nil, items: [])]
    end
    sections.each_with_index.map { |section, index| domain_node(section, first: index.zero?) }
  end

  private

  def unbound_forms?
    Admin::Pages::BrowseScope.call(customer_id: customer_id, unbound: true).exists?
  end

  def domain_node(section, first:)
    domain = section.domain
    domains_path = "/#{customer_id}/admin/domains"
    path = "#{domains_path}/#{Admin::Domains::Directory.key_for(domain)}"
    SidebarNode.new(
      key: "entities.domain.#{Admin::Domains::Directory.key_for(domain)}",
      label: domain ? domain.name : I18n.t("chrome.sidebar.entities.ungrouped"),
      menu_item: MENU_ITEM,
      path: path,
      match_prefix: path,
      match_paths: (first ? [domains_path] : []),
      icon: ICONS[domain ? :domain : :ungrouped],
      tone: (SidebarTone.domain(domain.color) if domain),
      children: entity_nodes(section.items.map(&:entity))
    )
  end

  def entity_nodes(entities)
    EntityDomains::EntityOrder.sort(entities).map do |entity|
      path = "/#{customer_id}/admin/entities/#{entity.id}"
      SidebarNode.new(key: "entities.#{entity.id}", label: entity.display_label, menu_item: MENU_ITEM,
                      path: path, match_prefix: path)
    end
  end
end
