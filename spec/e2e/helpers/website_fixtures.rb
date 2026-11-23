# frozen_string_literal: true

# Called only through the isolated-database Rails runner. Every test owns two
# draft pages; existing marketing pages, publication and catalogs are retained.
module WebsiteBrowserFixtures
  module_function

  def context(token)
    raise ArgumentError, "Invalid Website fixture token" unless token.match?(/\A[a-f0-9]{32}\z/)

    customer = Customer.find(81721200)
    raise "Website module must already be enabled" unless FeatureModules::Website::Registration.enabled_for?(customer.id)
    raise "Pinned platform owner required" unless customer.users.find_by!(email: "lingercoffee@gmail.com").platform_owner?

    [customer, Website.for_customer(customer.id).first!]
  end

  def create(token)
    customer, site = context(token)
    Current.with_customer(customer) do
      WebsitePage.transaction do
        gallery = WebsiteLayout.active.find_by!(key: "gallery")
        gallery_sections = gallery.instantiate_sections.deep_dup
        raise "Gallery fixture must use the current four-section schema" unless gallery_sections.map { |section| section.fetch("type") } == %w[hero_cinematic card_grid quote cta_band]

        split_layout = WebsiteLayout.active.find_by!(key: "longform")
        split_sections = [split_layout.instantiate_sections.find { |section| section.fetch("type") == "split_image_text" }.deep_dup]
        raise "Split-image fixture missing from current layout" unless split_sections.first

        pages = { gallery: [gallery, gallery_sections], split: [split_layout, split_sections] }.to_h do |name, (layout, sections)|
          sections.each_with_index { |section, index| section["id"] = "qa_#{token}_#{name}_#{index}" }
          page = site.pages.new(customer: customer)
          result = Websites::Activities::SavePage.call(page: page, structure_editable: true, params: {
            title: "Website browser #{name} #{token}", slug: "qa-website-#{token}-#{name}", layout_key: layout.key,
            home: false, nav_visible: false, published: false, sections: sections
          })
          raise "Website fixture failed: #{result.errors.join(', ')}" unless result.success?

          [name, { id: page.id, edit: "/#{customer.id}/admin/modules/website/pages/#{page.id}/edit", preview: "/#{customer.id}/admin/modules/website/pages/#{page.id}/preview" }]
        end
        home = site.pages.find_by!(home: true)
        { token: token, website_id: site.id, pages: pages, home_edit: "/#{customer.id}/admin/modules/website/pages/#{home.id}/edit" }
      end
    end
  end

  def snapshot(token, name)
    customer, site = context(token)
    page = site.pages.find_by!(customer: customer, slug: "qa-website-#{token}-#{name}")
    page.attributes.slice("id", "website_id", "customer_id", "title", "slug", "layout_key", "home", "published", "nav_visible", "sections")
  end

  def cleanup(token)
    customer, site = context(token)
    # Exact test-owned identities only: no prefix-wide deletion or shared restore.
    site.pages.where(customer: customer, slug: %w[gallery split].map { |name| "qa-website-#{token}-#{name}" }).find_each(&:destroy!)
  end
end
