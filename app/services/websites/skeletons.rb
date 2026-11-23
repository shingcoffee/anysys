# frozen_string_literal: true

require "ulid"

module Websites
  # Code-defined starter compositions. Tenants clone these into website_pages
  # at provision (and on explicit replace). Catalog labels are I18n; body copy
  # is English stored in JSON.
  module Skeletons
    KEYS = %w[
      presence saas_landing cinematic editorial studio product ledger signal atelier campus gazette
      lumen monograph terrain supper clinic folio voyage kinetic
      voltage wellspring summit manor bloom roast atrium
      canvas harbor calm marque tempo quarterly
    ].freeze

    CATEGORIES = %w[business product commerce hospitality editorial portfolio wellness education nonprofit events culture].freeze

    CATEGORY_BY_KEY = {
      "presence" => "business",
      "saas_landing" => "product",
      "cinematic" => "product",
      "editorial" => "editorial",
      "studio" => "hospitality",
      "product" => "product",
      "ledger" => "product",
      "signal" => "product",
      "atelier" => "business",
      "campus" => "education",
      "gazette" => "editorial",
      "lumen" => "product",
      "monograph" => "editorial",
      "terrain" => "business",
      "supper" => "hospitality",
      "clinic" => "wellness",
      "folio" => "portfolio",
      "voyage" => "hospitality",
      "kinetic" => "wellness",
      "voltage" => "product",
      "wellspring" => "nonprofit",
      "summit" => "events",
      "manor" => "business",
      "bloom" => "commerce",
      "roast" => "hospitality",
      "atrium" => "culture",
      "canvas" => "product",
      "harbor" => "commerce",
      "calm" => "wellness",
      "marque" => "product",
      "tempo" => "culture",
      "quarterly" => "editorial"
    }.freeze

    module_function

    def keys
      KEYS
    end

    def category_for(key)
      CATEGORY_BY_KEY.fetch(key.to_s, "business")
    end

    def categories
      CATEGORIES.select { |category| KEYS.any? { |key| category_for(key) == category } }
    end

    def known?(key)
      Websites::Catalog.known_skeleton?(key)
    end

    def [](key)
      registry[key.to_s]
    end

    def pages_for(key)
      row = WebsiteSkeleton.table_exists? ? WebsiteSkeleton.active.find_by(key: key.to_s) : nil
      return row.page_list if row

      seed_pages_for(key)
    end

    def seed_pages_for(key)
      klass = self[key]
      klass ? klass::PAGES : []
    end

    def home_sections(key, pages = nil, limit: nil)
      specs = Array(pages.presence || pages_for(key)).select { |page| page.respond_to?(:stringify_keys) }.map(&:stringify_keys)
      home = specs.find { |page| ActiveModel::Type::Boolean.new.cast(page["home"]) } || specs.first
      sections = Array(home&.dig("sections"))
      decorate_sections(limit ? sections.first(limit) : sections)
    end

    def apply!(website, skeleton_key, replace: false)
      PageShortcuts::Collisions.with_customer_lock(customer_id: website.customer_id) do
        Website.for_customer(website.customer_id).scoping(all_queries: true) { website.reload }
        if WebsiteSkeleton.where(key: skeleton_key.to_s, archived: true).exists?
          website.errors.add(:base, I18n.t("website.errors.unknown_skeleton"))
          raise ActiveRecord::RecordInvalid, website
        end
        pages = pages_for(skeleton_key)
        contract = Contracts::Skeleton.new(Contracts::Skeleton::Input.new(pages))
        unless contract.validate({})
          contract.errors.full_messages.each { |message| website.errors.add(:base, message) }
          raise ActiveRecord::RecordInvalid, website
        end

        # All writes reserving a clean slug share the customer lock. Validate
        # the complete replacement BEFORE removing the customer's existing work.
        pages.each do |page|
          if PageShortcuts::Collisions.website_slug_taken?(slug: page["slug"], customer_id: website.customer_id)
            website.errors.add(:base, I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
          end
          if !replace && website.pages.exists?(slug: page["slug"])
            website.errors.add(:base, I18n.t("website.errors.slug_taken"))
          end
        end
        raise ActiveRecord::RecordInvalid, website if website.errors.any?

        website.pages.destroy_all if replace
        pages.each_with_index.map do |page, index|
          website.pages.create!(
            customer_id: website.customer_id,
            title: page["title"],
            slug: page["slug"],
            home: page["home"],
            nav_visible: page.fetch("nav_visible", true),
            published: false,
            position: index,
            layout_key: page["layout_key"],
            sections: decorate_sections(page["sections"])
          )
        end
      end
    end

    def decorate_sections(sections, palette = nil)
      Websites::Media.fill_sections(sections, palette)
    end

    def registry
      {
        "presence" => Presence,
        "saas_landing" => SaasLanding,
        "cinematic" => Cinematic,
        "editorial" => Editorial,
        "studio" => Studio,
        "product" => Product,
        "ledger" => Ledger,
        "signal" => Signal,
        "atelier" => Atelier,
        "campus" => Campus,
        "gazette" => Gazette,
        "lumen" => Lumen,
        "monograph" => Monograph,
        "terrain" => Terrain,
        "supper" => Supper,
        "clinic" => Clinic,
        "folio" => Folio,
        "voyage" => Voyage,
        "kinetic" => Kinetic,
        "voltage" => Voltage,
        "wellspring" => Wellspring,
        "summit" => Summit,
        "manor" => Manor,
        "bloom" => Bloom,
        "roast" => Roast,
        "atrium" => Atrium,
        "canvas" => Canvas,
        "harbor" => Harbor,
        "calm" => Calm,
        "marque" => Marque,
        "tempo" => Tempo,
        "quarterly" => Quarterly
      }
    end
  end
end
