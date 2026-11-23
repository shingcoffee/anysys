# frozen_string_literal: true

module Websites
  module Activities
    class SavePage
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      KEYS = %i[title slug published nav_visible home sections layout_key theme_key].freeze
      # New-page choice meaning "use the picked layout's paired theme".
      LAYOUT_THEME = "layout"

      def self.call(page:, params:, structure_editable: false)
        PageShortcuts::Collisions.with_customer_lock(customer_id: page.customer_id) do
          if page.persisted?
            WebsitePage.for_customer(page.customer_id).scoping(all_queries: true) { page.reload }
          end
          save(page: page, params: params, structure_editable: structure_editable)
        end
      rescue ActiveRecord::RecordNotFound
        failure(page, :base, I18n.t("page_shortcuts.errors.invalid_customer"))
      rescue ActiveRecord::RecordNotUnique
        failure(page, :slug, I18n.t("website.errors.slug_taken"))
      rescue ActiveRecord::RecordInvalid
        Result.new(success?: false, model: page, errors: page.errors.full_messages)
      end

      def self.save(page:, params:, structure_editable:)
        attrs = sanitize(params)
        if attrs[:sections] == :invalid
          return failure(page, :sections, I18n.t("website.errors.invalid_sections"))
        end
        if unsetting_home?(page, attrs)
          return failure(page, :home, I18n.t("website.errors.home_required"))
        end
        if attrs[:layout_key].present? && (structure_editable || !page.persisted?) &&
            !Websites::Catalog.known_layout?(attrs[:layout_key])
          return failure(page, :layout_key, I18n.t("website.errors.unknown_layout"))
        end

        make_home = attrs.key?(:home) && ActiveModel::Type::Boolean.new.cast(attrs[:home])
        if make_home
          attrs[:home] = true
          attrs[:slug] = ""
        else
          page.title = attrs[:title] if attrs.key?(:title)
          if !page.persisted? || attrs.key?(:slug)
            attrs[:slug] = unique_slug_for(page) if attrs[:slug].to_s.blank?
          end
        end

        unless structure_editable
          if page.persisted? && page.layout_key.present?
            attrs.delete(:layout_key)
          elsif page.persisted? && attrs.key?(:sections)
            inferred = Websites::Catalog.infer_layout_key(page.sections)
            if inferred.present?
              attrs[:layout_key] = inferred
            else
              attrs.delete(:layout_key)
            end
          elsif page.persisted?
            attrs.delete(:layout_key)
          else
            attrs[:layout_key] = resolve_layout_key(page, attrs)
          end
          attrs[:sections] = locked_sections(page, attrs) if attrs.key?(:sections) || !page.persisted?
        end
        attrs[:theme_key] = layout_theme_key(page, attrs) if attrs[:theme_key] == LAYOUT_THEME

        if attrs.key?(:sections) && (!page.persisted? || attrs[:sections] != page.sections)
          # Resolve locked IDs/types first. Decorating an ignored incoming type
          # can otherwise inject its image props into a different saved type.
          attrs[:sections] = Websites::Skeletons.decorate_sections(attrs[:sections])
        end

        page.assign_attributes(attrs)
        validate_sections = !page.persisted? || page.will_save_change_to_sections? || attrs[:published] == true
        contract = Websites::Contracts::Page.new(page, validate_sections: validate_sections)
        unless contract.validate(attrs.deep_stringify_keys)
          merge_errors!(page, contract.errors)
          return Result.new(success?: false, model: page, errors: page.errors.full_messages.presence || contract.errors.full_messages)
        end

        persist!(page, make_home: make_home)
      end
      private_class_method :save

      def self.sanitize(params)
        h = params.to_h.deep_symbolize_keys
        attrs = {}
        KEYS.each { |key| attrs[key] = h[key] if h.key?(key) }
        %i[published nav_visible home].each do |key|
          attrs[key] = ActiveModel::Type::Boolean.new.cast(attrs[key]) if attrs.key?(key)
        end
        if attrs.key?(:sections)
          parsed = parse_sections(attrs[:sections])
          attrs[:sections] = parsed
        end
        attrs[:theme_key] = attrs[:theme_key].to_s.presence if attrs.key?(:theme_key)
        attrs
      end

      def self.layout_theme_key(page, attrs)
        key = attrs[:layout_key].presence || page.layout_key
        return if key.blank?

        WebsiteLayout.find_by(key: key)&.theme_preset_key || Websites::ThemePairing.for_layout(key)
      end
      private_class_method :layout_theme_key

      def self.parse_sections(raw)
        return [] if raw.blank?
        return :invalid unless raw.is_a?(String) || raw.is_a?(Array)

        parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
        valid_shape = parsed.is_a?(Array) && parsed.all? do |section|
          section.is_a?(Hash) && (!section.key?("props") || section["props"].is_a?(Hash)) &&
            (!section.key?(:props) || section[:props].is_a?(Hash))
        end
        valid_shape ? parsed.map(&:deep_stringify_keys) : :invalid
      rescue JSON::ParserError
        :invalid
      end
      private_class_method :parse_sections

      def self.resolve_layout_key(page, attrs)
        attrs[:layout_key].presence ||
          page.layout_key.presence ||
          page.website&.default_layout_key.presence ||
          Websites::Catalog.layouts.first&.key
      end
      private_class_method :resolve_layout_key

      def self.locked_sections(page, attrs)
        incoming = attrs.key?(:sections) ? attrs[:sections] : nil
        layout_key = attrs[:layout_key].presence || page.layout_key
        template = Array(page.sections)
        return template if page.persisted? && incoming.blank?

        if template.empty? && layout_key.present?
          layout = WebsiteLayout.find_by(key: layout_key)
          template = Array(layout&.instantiate_sections)
        end
        return template if incoming.blank?

        incoming_by_id = Array(incoming).each_with_object({}) do |raw, acc|
          hash = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
          acc[hash["id"].to_s] = hash if hash["id"].present?
        end
        merged = template.map do |raw|
          section = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
          update = incoming_by_id[section["id"].to_s]
          next section unless update

          props = (update["props"] || {}).to_h.stringify_keys
          section.merge("type" => section["type"], "props" => props)
        end
        merged
      end
      private_class_method :locked_sections

      def self.persist!(page, make_home:)
        demote_sibling_homes!(page) if make_home
        page.save!
        Result.new(success?: true, model: page, errors: [])
      end
      private_class_method :persist!

      def self.failure(page, attribute, message)
        page.errors.add(attribute, message)
        Result.new(success?: false, model: page, errors: page.errors.full_messages)
      end
      private_class_method :failure

      def self.merge_errors!(page, from)
        from.each { |error| page.errors.add(error.attribute, error.message) }
      end
      private_class_method :merge_errors!

      def self.unsetting_home?(page, attrs)
        return false unless page.home?
        return false unless attrs.key?(:home)

        !ActiveModel::Type::Boolean.new.cast(attrs[:home])
      end
      private_class_method :unsetting_home?

      def self.demote_sibling_homes!(page)
        scope = page.website.pages.where(home: true)
        scope = scope.where.not(id: page.id) if page.persisted?
        scope.find_each do |sibling|
          sibling.home = false
          sibling.slug = unique_slug_for(sibling) if sibling.slug.blank?
          sibling.save!
        end
      end
      private_class_method :demote_sibling_homes!

      def self.unique_slug_for(page)
        base = page.title.to_s.parameterize.presence || "page"
        base = "page" if WebsitePage::RESERVED_SLUGS.include?(base)
        candidate = base
        index = 2
        taken = page.website.pages
        taken = taken.where.not(id: page.id) if page.persisted?
        while taken.exists?(slug: candidate) || PageShortcuts::Collisions.website_slug_taken?(
          slug: candidate, customer_id: page.customer_id, page_id: page.id
        )
          candidate = "#{base}-#{index}"
          index += 1
        end
        candidate
      end
      private_class_method :unique_slug_for
    end
  end
end
