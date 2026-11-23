# frozen_string_literal: true

require "set"

module PageShortcuts
  # One explicit customer's immutable presentation snapshot. Batch scalar reads
  # avoid definition callbacks and per-link eligibility/association queries.
  # Routing and write validation never use this snapshot.
  class Lookup
    WebsiteIdentity = Data.define(:id, :customer_id, :slug, :home, :published, :site_published) do
      def home? = home
    end
    ShortcutIdentity = Data.define(:customer_id, :path, :target_type, :target_id)
    PublicPageIdentity = Data.define(:id, :customer_id, :public_uuid)

    attr_reader :customer_id, :home_page, :host, :host_customer_id

    def initialize(customer_id:, host: nil, include_titles: false)
      @customer_id = customer_id
      # Capture only this rendering scope's host selection, never a registry.
      # Hosts remains live for routing and callers outside this snapshot.
      @host = Hosts.normalize(host)&.freeze
      @host_customer_id = Hosts.customer_id(host)
      active = Customer.exists?(id: customer_id)
      @website_enabled = active && FeatureModules::Module.enabled?(key: "website", customer_id: customer_id)
      titles = {}
      columns = [:id, :slug, :home, :published, "websites.published"]
      columns << :title if include_titles
      pages = WebsitePage.joins(:website).where(customer_id: customer_id, websites: { customer_id: customer_id })
                         .pluck(*columns)
      @pages = pages.to_h do |id, slug, home, published, site_published, title|
        titles[["WebsitePage", id].freeze] = title&.freeze if include_titles
        [id, WebsiteIdentity.new(id: id, customer_id: customer_id, slug: slug.dup.freeze,
                                 home: home, published: published, site_published: site_published)]
      end.freeze
      @pages_by_slug = @pages.values.to_h { |page| [page.slug, page] }.freeze
      @home_page = @pages.values.find(&:home?)
      rows = PageShortcut.for_customer(customer_id).by_path.pluck(:path, :target_type, :target_id)
      @shortcuts = rows.to_h do |path, type, id|
        [path.freeze, ShortcutIdentity.new(customer_id: customer_id, path: path, target_type: type.freeze, target_id: id)]
      end.freeze
      if include_titles
        saved_ids = rows.filter_map { |_path, type, id| id if type == "Page" }.uniq
        # Saved identities remain visible when offline/deleted, but never leak
        # another tenant's name or instantiate a versioned Page definition.
        Page.with_deleted.where(id: saved_ids, customer_id: [customer_id, nil]).pluck(:id, :name).each do |id, name|
          titles[["Page", id].freeze] = name&.freeze
        end
      end
      @titles = titles.freeze
      # Include eligible pages with no shortcuts: canonical UUID links in site
      # navigation/footer must not trigger a model/definition load per link.
      public_pages = if active
        Page.where(customer_id: [customer_id, nil], status: :active, launched: true).for_audience("public")
            .pluck(:id, :customer_id, :public_uuid).filter_map do |id, owner_id, uuid|
          PublicPageIdentity.new(id: id, customer_id: owner_id, public_uuid: uuid.dup.freeze) if uuid.present?
        end
      else
        []
      end
      @public_ids = Set.new(public_pages.map(&:id)).freeze
      @public_pages_by_uuid = public_pages.to_h { |page| [page.public_uuid, page] }.freeze
      @aliases = @shortcuts.values.each_with_object({}) do |shortcut, aliases|
        next unless shortcut_available?(shortcut)

        aliases[[shortcut.target_type, shortcut.target_id].freeze] ||= shortcut.path
      end.freeze
      freeze
    end

    def page_for_slug(slug)
      @pages_by_slug[slug]
    end

    def shortcut_at(path)
      @shortcuts[path]
    end

    def alias_path(type, id)
      @aliases[[type, id]]
    end

    def public_page_for_uuid(uuid)
      @public_pages_by_uuid[uuid]
    end

    def target_title(type, id)
      @titles[[type, id]]
    end

    def shortcut_available?(shortcut)
      return false unless shortcut.customer_id == customer_id

      path = PathPolicy.normalize(shortcut.path, leading_slash: false)
      !!(path && path == shortcut.path && !PathPolicy.reserved?(path) &&
        eligible?(shortcut.target_type, shortcut.target_id) && !collision?(shortcut))
    end

    private

    def eligible?(type, id)
      case type
      when "WebsitePage"
        page = @pages[id]
        @website_enabled && page && page.published && page.site_published &&
          (page.home? || PathPolicy::SEGMENT.match?(page.slug))
      when "Page"
        @public_ids.include?(id)
      else
        false
      end
    end

    def collision?(shortcut)
      path = shortcut.path
      return false if path == "/" || !PathPolicy.automatic?(path)

      page = page_for_slug(path.delete_prefix("/"))
      page && !page.home? && !Collisions.same_website_target?(
        target_type: shortcut.target_type, target_id: shortcut.target_id, page_id: page.id
      )
    end
  end
end
