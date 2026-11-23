# frozen_string_literal: true

module Websites
  # Explicit source restore for the platform's editable marketing site.
  # Translations are resolved at call time and persisted as ordinary strings.
  module HomeSite
    CUSTOMER_ID = 81_721_200
    SIGNUP = "/auth/sign_up".freeze
    PAGE_KEYS = %w[home platform pricing about contact].freeze
    THEME = { "appearance" => "light", "accent" => "violet", "type" => "sans", "density" => "compact" }.freeze
    # Changed-type predecessors can only identify an opaque legacy section when
    # exactly one remaining source role and one predecessor fit that type.
    LEGACY_SECTION_TYPES = {
      "home" => { "hero" => "hero_cinematic", "website" => "bento_grid" }.freeze,
      "platform" => { "capabilities" => "bento_grid", "steps" => "alternating_features" }.freeze,
      "about" => { "principles" => "bento_grid", "craft" => "rich_text" }.freeze
    }.freeze

    module_function

    def definition(locale: :en)
      Definition.new(locale).call
    end

    # Deliberately accepts no customer override. Nothing on the read path calls
    # this method; explicit reapplication replaces source-page owner edits.
    def apply!(locale: :en)
      source = definition(locale: locale)
      Customer.find(CUSTOMER_ID).with_lock do
        feature_module = FeatureModules::Module.find_by(key: "website")
        unless feature_module&.active?
          raise FeatureModules::ModuleNotEnabled, I18n.t("website.home_site.errors.module_unavailable", locale: locale)
        end

        site = Website.find_or_initialize_by(customer_id: CUSTOMER_ID)
        site.skeleton_key = "presence" if site.new_record?
        result = Websites::Activities::SaveSite.call(site: site, params: source.except("pages"))
        unless result.success?
          result.errors.each { |error| site.errors.add(:base, error) }
          raise ActiveRecord::RecordInvalid, site
        end

        # Same assignment convention as ModuleEnablementsController. Creating
        # the site first makes normal provisioning a no-op (no starter pages).
        assignment = FeatureModules::CustomerAssignment.find_or_initialize_by(
          customer_id: CUSTOMER_ID, feature_module: feature_module
        )
        unless assignment.persisted? && assignment.active?
          assignment.update!(status: :active, enabled_at: Time.current,
                             configuration: assignment.configuration.presence || {}.to_json)
        end
        feature_module.registration_class.provision!(site.customer)

        source.fetch("pages").each_with_index do |page_definition, index|
          save_page!(site, page_definition, position: index + 1)
        end
        site.reload
      end
    end

    def save_page!(site, definition, position:)
      page = definition.fetch("home") ? site.home_page : site.pages.find_by(slug: definition.fetch("slug"))
      page ||= site.pages.build(customer_id: CUSTOMER_ID)
      page.position = position
      params = definition.merge("published" => true, "nav_visible" => true)
      params["sections"] = preserve_section_ids(page.sections, definition.fetch("sections"))
      result = Websites::Activities::SavePage.call(page: page, params: params, structure_editable: true)
      raise ActiveRecord::RecordInvalid, page unless result.success?

      # SavePage reloads persisted pages under its write lock; apply this
      # restore-only ordering explicitly rather than relying on dirty state.
      page.update!(position: position) unless page.position == position
    end
    private_class_method :save_page!

    def preserve_section_ids(existing, sections)
      remaining = Array(existing).select { |item| item["id"].present? }
      source_ids = sections.pluck("id")
      matches = {}
      used_ids = Set.new
      reserve = lambda do |section, previous|
        matches[section.fetch("id")] = previous.fetch("id")
        used_ids.add(previous.fetch("id"))
        remaining.reject! { |item| item["id"] == previous["id"] }
      end

      # Finish identity/role matching for every section before type fallback can
      # claim a later section's predecessor. Types, positions and copy may change.
      sections.each do |section|
        previous = remaining.find { |item| item["id"] == section["id"] }
        reserve.call(section, previous) if previous
      end
      sections.each do |section|
        next if matches.key?(section["id"])

        role = section_role(section["id"])
        candidates = remaining.select { |item| role && section_role(item["id"]) == role }
        reserve.call(section, candidates.first) if candidates.one?
      end

      unmatched = sections.reject { |section| matches.key?(section["id"]) }
      # An actual source id describes a role even if that role was removed. Do
      # not borrow it for a different role with the same type (e.g. About craft).
      opaque = remaining.reject { |item| section_role(item["id"]) || source_ids.include?(item["id"]) || used_ids.include?(item["id"]) }
      unmatched.each do |section|
        candidates = opaque.select { |item| predecessor_types(section).include?(item["type"]) }
        next unless candidates.one?

        previous = candidates.first
        next unless unmatched.count { |item| predecessor_types(item).include?(previous["type"]) } == 1

        reserve.call(section, previous)
        opaque.reject! { |item| item["id"] == previous["id"] }
      end
      sections.map { |section| section.merge("id" => matches.fetch(section["id"], section.fetch("id"))) }
    end
    private_class_method :preserve_section_ids

    def section_role(id)
      match = /\Ahome_site_(#{PAGE_KEYS.join('|')})_([a-z]+(?:_[a-z]+)*)\z/.match(id.to_s)
      match&.captures
    end
    private_class_method :section_role

    def predecessor_types(section)
      page, role = section_role(section["id"])
      [section["type"], LEGACY_SECTION_TYPES.dig(page, role)].compact
    end
    private_class_method :predecessor_types

    class Definition
      def initialize(locale)
        @locale = locale
      end

      def call
        {
          "name" => copy("brand"), "tagline" => copy("tagline"),
          "theme" => THEME.dup, "seo" => copy("seo"), "footer" => footer,
          "published" => true,
          "pages" => PAGE_KEYS.map do |key|
            { "title" => copy("pages.#{key}"), "slug" => key == "home" ? "" : key,
              "home" => key == "home", "sections" => sections(key) }
          end
        }
      end

      private

      def copy(key, **values)
        value = I18n.t("website.home_site.#{key}", locale: @locale, raise: true, **values)
        value.is_a?(Hash) ? value.deep_stringify_keys : value
      end

      def section(page, id, type, props)
        { "id" => "home_site_#{page}_#{id}", "type" => type, "props" => props }
      end

      def hero(page)
        props = copy(page == "home" ? "hero" : "#{page}.hero")
        actions = if %w[home platform about].include?(page)
          secondary = page == "platform" ? "pricing" : "platform"
          { "primary_label" => copy("actions.start"), "primary_href" => SIGNUP,
            "secondary_label" => copy(secondary == "pricing" ? "actions.pricing" : "actions.explore"),
            "secondary_href" => secondary }
        else
          %w[primary_label primary_href secondary_label secondary_href].index_with { "" }
        end
        media_mode = %w[about contact].include?(page) ? "image" : "none"
        section(page, "hero", "hero_centered", props.merge("media_mode" => media_mode).merge(actions))
      end

      def preview(page)
        props = copy("preview.#{page}").merge(
          "example_label" => copy("preview.example"), "prompt_label" => copy("preview.prompt_label"),
          "output_label" => copy("preview.output_label"), "review_note" => copy("preview.review_note")
        )
        props["items"].each { |item| item["status"] = copy("preview.draft") }
        section(page, "preview", "ai_preview", props)
      end

      def assistant(page) = section(page, "assistant", "feature_grid", copy("assistant"))

      def desktop(page)
        props = copy("desktop.panel").merge("kicker" => copy("desktop.status"), "heading" => copy("desktop.headline"))
        props["cards"].each { |card| card["href"] = "" }
        section(page, "desktop", "card_grid", props)
      end

      def pricing
        section("pricing", "plans", "pricing", copy("pricing.section").merge(
          "featured_label" => copy("pricing.recommended"),
          "tiers" => tiers
        ))
      end

      def tiers
        Billing::StandardPlans::CATALOG.map do |plan|
          key = plan.fetch(:code).delete_suffix("-monthly")
          features = plan.fetch(:limits).slice("page", "entity", "member").map do |resource, limit|
            if limit == Billing::PlanLimit::UNLIMITED
              copy("pricing.limits.#{resource}.unlimited")
            else
              copy("pricing.limits.#{resource}.limited", count: limit)
            end
          end
          features << copy("pricing.trial", count: plan.fetch(:trial_days)) if plan.fetch(:trial_days).positive?
          copy("pricing.plans.#{key}").merge(
            "price" => copy("pricing.price", amount: format("%g", plan.fetch(:amount_usd))),
            "cadence" => copy("pricing.cadence"), "features" => features.join("\n"),
            "button_label" => copy("actions.start"), "button_href" => SIGNUP,
            "highlight" => key == "starter" ? "featured" : "standard"
          )
        end
      end

      def content(page, id, type, key = "#{page}.#{id}")
        section(page, id, type, copy(key))
      end

      def cta(page)
        section(page, "cta", "cta_band", copy("#{page}.cta").merge(
          "button_label" => copy("actions.create"), "button_href" => SIGNUP
        ))
      end

      def sections(page)
        middle = case page
        when "home"
          [content(page, "stats", "proof_strip"), content(page, "industries", "logo_cloud"), preview(page), assistant(page),
           desktop(page), content(page, "capabilities", "feature_grid"), content(page, "website", "split_image_text"),
           content(page, "steps", "steps"), content(page, "faq", "faq")]
        when "platform"
          [preview(page), assistant(page), desktop(page), content(page, "capabilities", "feature_grid"),
           content(page, "website", "split_image_text"), content(page, "comparison", "comparison_table"),
           section(page, "steps", "steps", copy("platform.steps").merge("items" => copy("home.steps").fetch("items")))]
        when "pricing"
          [pricing, content(page, "foundation", "feature_grid"), content(page, "faq", "faq")]
        when "about"
          [content(page, "stats", "proof_strip"), content(page, "mission", "rich_text"), content(page, "principles", "feature_grid"),
           content(page, "craft", "split_image_text")]
        when "contact"
          [content(page, "availability", "rich_text")]
        end
        [hero(page), *middle, cta(page)]
      end

      def footer
        columns = {
          "product" => [["pages.platform", "platform"], ["pages.pricing", "pricing"], ["actions.start", SIGNUP]],
          "company" => [["pages.about", "about"], ["pages.contact", "contact"]],
          "desktop" => [["footer.desktop_link", "platform"]]
        }.map do |key, links|
          { "heading" => copy("footer.#{key}"),
            "links" => links.map { |label, url| { "label" => copy(label), "url" => url } } }
        end
        { "blurb" => copy("footer.blurb"), "columns" => columns }
      end
    end
    private_constant :Definition
  end
end
