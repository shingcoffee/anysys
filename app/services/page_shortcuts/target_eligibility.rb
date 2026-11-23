# frozen_string_literal: true

module PageShortcuts
  module TargetEligibility
    module_function

    def eligible?(target, customer_id:)
      type, id = if target.is_a?(PageShortcut)
        return false unless target.customer_id == PathPolicy.customer_id(customer_id)

        [target.target_type, target.target_id]
      elsif target.is_a?(WebsitePage) || target.is_a?(Page)
        [target.class.base_class.name, target.id]
      else
        return false
      end
      resolve(type: type, id: id, customer_id: customer_id).present?
    end

    def website_pages(customer_id:)
      cid = PathPolicy.customer_id(customer_id)
      return WebsitePage.none unless cid && Customer.exists?(id: cid)
      return WebsitePage.none unless FeatureModules::Module.enabled?(key: "website", customer_id: cid)

      WebsitePage.joins(:website).where(customer_id: cid, published: true,
                                      websites: { customer_id: cid, published: true })
    end

    def public_pages(customer_id:)
      cid = PathPolicy.customer_id(customer_id)
      return Page.none unless cid && Customer.exists?(id: cid)

      # Do not use Page.accessible: it infers a tenant from Current. Public routing
      # only needs identity, so pick/pluck avoids Page's after_find definition read.
      Page.where(customer_id: [cid, nil], status: :active, launched: true).for_audience("public")
    end

    def resolve(type:, id:, customer_id:)
      cid = PathPolicy.customer_id(customer_id)
      return unless cid && id.to_s.match?(/\A[1-9][0-9]*\z/)

      case type
      when "WebsitePage"
        row = website_pages(customer_id: cid).where(id: id).pick(:id, :slug, :home)
        website_target(row, customer_id: cid) if row
      when "Page"
        row = public_pages(customer_id: cid).where(id: id).pick(:id, :public_uuid)
        return unless row && row[1].present?

        Target.new(customer_id: cid, target_type: "Page", target_id: row[0],
                   controller: "public_pages", action: "show", page_slug: nil, uuid: row[1],
                   canonical_path: "/#{cid}/page/#{row[1]}")
      end
    end

    def website_target(row, customer_id:)
      id, slug, home = row
      return unless home || (slug.is_a?(String) && PathPolicy::SEGMENT.match?(slug))

      Target.new(customer_id: customer_id, target_type: "WebsitePage", target_id: id,
                 controller: "websites/pages", action: home ? "home" : "show",
                 page_slug: home ? nil : slug, uuid: nil,
                 canonical_path: home ? "/#{customer_id}/site" : "/#{customer_id}/site/#{slug}")
    end
    private_class_method :website_target
  end
end
