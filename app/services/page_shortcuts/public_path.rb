# frozen_string_literal: true

module PageShortcuts
  # All results are unmounted Rails paths. Request-facing callers add SCRIPT_NAME
  # and preserve query/fragment/locale through Addressable at rendering time.
  module PublicPath
    UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

    module_function

    def with_lookup(customer_id:, host: nil)
      cid = PathPolicy.customer_id(customer_id)
      return yield unless cid

      snapshot = lookup_for(cid)
      snapshot = Lookup.new(customer_id: cid, host: host) unless snapshot && snapshot.host == Hosts.normalize(host)
      Current.set(page_shortcuts_lookup: snapshot) { yield }
    end

    def website_home(customer_id:, host: nil)
      cid = PathPolicy.customer_id(customer_id)
      return unless cid

      lookup = lookup_for(cid)
      page = lookup ? lookup.home_page : WebsitePage.where(customer_id: cid, home: true).first
      return website_page(page: page, host: host) if page
      root = lookup ? lookup.shortcut_at("/") : PageShortcut.for_customer(cid).find_by(path: "/")
      return "/#{cid}/site" if root

      host_path("/", customer_id: cid, host: host)
    end

    def website_page(page:, host: nil)
      cid = PathPolicy.customer_id(page.customer_id)
      return unless cid

      aliased = explicit_path(type: "WebsitePage", id: page.id, customer_id: cid, host: host)
      return aliased if aliased

      path = page.home? ? "/" : "/#{page.slug}"
      if PathPolicy.automatic?(path) && automatic_available_for?(page, cid, path)
        host_path(path, customer_id: cid, host: host)
      else
        page.home? ? "/#{cid}/site" : "/#{cid}/site/#{page.slug}"
      end
    end

    def website_slug(slug:, customer_id:, host: nil)
      cid = PathPolicy.customer_id(customer_id)
      return unless cid

      return website_home(customer_id: cid, host: host) if slug.to_s.empty?
      return unless slug.is_a?(String) && PathPolicy::SEGMENT.match?(slug)

      lookup = lookup_for(cid)
      page = lookup ? lookup.page_for_slug(slug) : WebsitePage.where(customer_id: cid, slug: slug).first
      return website_page(page: page, host: host) if page

      path = "/#{slug}"
      shortcut = lookup ? lookup.shortcut_at(path) : PageShortcut.for_customer(cid).find_by(path: path)
      if PathPolicy.automatic?(path) && !shortcut
        host_path(path, customer_id: cid, host: host)
      else
        "/#{cid}/site/#{slug}"
      end
    end

    def public_page(page:, customer_id:, host: nil)
      cid = PathPolicy.customer_id(customer_id)
      return unless cid && page.public_uuid.present? && (page.customer_id.nil? || page.customer_id == cid)

      explicit_path(type: "Page", id: page.id, customer_id: cid, host: host) ||
        "/#{cid}/page/#{page.public_uuid}"
    end

    # Eligible UUID destinations only. Nil leaves an unrelated/unavailable
    # canonical href intact. Neither path instantiates a Page or reads definitions.
    def public_page_uuid(uuid:, customer_id:, host: nil)
      cid = PathPolicy.customer_id(customer_id)
      return unless cid && uuid.is_a?(String) && UUID.match?(uuid)

      lookup = lookup_for(cid)
      page = if lookup
        lookup.public_page_for_uuid(uuid)
      else
        row = TargetEligibility.public_pages(customer_id: cid).where(public_uuid: uuid).pick(:id, :customer_id, :public_uuid)
        Lookup::PublicPageIdentity.new(id: row[0], customer_id: row[1], public_uuid: row[2].dup.freeze) if row
      end
      public_page(page: page, customer_id: cid, host: host) if page
    end

    def shortcut(shortcut:, host: nil)
      path = PathPolicy.normalize(shortcut.path, leading_slash: false)
      return unless path == shortcut.path && path && !PathPolicy.reserved?(path)

      host_path(path, customer_id: shortcut.customer_id, host: host)
    end

    def explicit_path(type:, id:, customer_id:, host:)
      return if id.nil?
      if (lookup = lookup_for(customer_id))
        path = lookup.alias_path(type, id)
        return host_path(path, customer_id: customer_id, host: host) if path

        return nil
      end
      return unless TargetEligibility.resolve(type: type, id: id, customer_id: customer_id)

      candidate = PageShortcut.for_customer(customer_id).where(target_type: type, target_id: id).by_path.detect do |row|
        path = PathPolicy.normalize(row.path, leading_slash: false)
        path == row.path && !PathPolicy.reserved?(path) &&
          !Collisions.shortcut_conflict?(path: path, customer_id: customer_id, target_type: type, target_id: id)
      end
      shortcut(shortcut: candidate, host: host) if candidate
    end
    private_class_method :explicit_path

    def automatic_available_for?(page, customer_id, path)
      lookup = lookup_for(customer_id)
      shortcut = lookup ? lookup.shortcut_at(path) : PageShortcut.for_customer(customer_id).find_by(path: path)
      shortcut.nil? || (shortcut.target_type == "WebsitePage" && shortcut.target_id == page.id)
    end
    private_class_method :automatic_available_for?

    def host_path(path, customer_id:, host:)
      lookup = lookup_for(customer_id)
      return Hosts.path(path, customer_id: customer_id, host: host) unless lookup && lookup.host == Hosts.normalize(host)

      prefix = lookup.host_customer_id == customer_id ? "" : "/#{customer_id}"
      "#{prefix}#{path}"
    end
    private_class_method :host_path

    def lookup_for(customer_id)
      lookup = Current.page_shortcuts_lookup
      lookup if lookup&.customer_id == customer_id
    end
    private_class_method :lookup_for
  end
end
