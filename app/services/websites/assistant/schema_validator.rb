# frozen_string_literal: true

module Websites
  module Assistant
    # Normalizes an `apply_website` document against the section kit, the
    # tenant's website and the conversation's uploads. Every problem is
    # collected (up to MAX_ERRORS) so a single repair round can fix them all.
    # Values that fail a check are dropped from the normalized pages, which
    # still carry `upload:N` tokens — Processor swaps them for site-media URLs
    # at write time.
    class SchemaValidator
      Result = Struct.new(:errors, :pages, :unplaced, keyword_init: true)

      MAX_ERRORS = 20

      Head = Struct.new(:source, :title, :label, :record, :home, :slug, keyword_init: true)
      SectionModel = Struct.new(:id, :type, :props)
      BOOLEAN = ActiveModel::Type::Boolean.new
      private_constant :Head, :SectionModel, :BOOLEAN

      def self.call(extraction:, website:, uploads:)
        new(extraction: extraction, website: website, uploads: uploads).call
      end

      def self.image_values(node)
        values = []
        map_images(node) { |value| values << value }
        values
      end

      # Deep copy of `node` with every string under a SectionKit::IMAGE_KEYS key replaced
      # by the block's return value.
      def self.map_images(node, &block)
        case node
        when Hash
          node.to_h do |key, value|
            image = Websites::SectionKit::IMAGE_KEYS.include?(key.to_s) && value.is_a?(String)
            [key, image ? block.call(value) : map_images(value, &block)]
          end
        when Array
          node.map { |value| map_images(value, &block) }
        else
          node
        end
      end

      def initialize(extraction:, website:, uploads:)
        @extraction = extraction
        @website = website
        @uploads = uploads
        @errors = []
        @seen_page_ids = []
        @seen_slugs = []
      end

      def call
        pages = normalized_pages
        Result.new(errors: @errors, pages: pages, unplaced: unplaced_in(pages))
      end

      private

      def normalized_pages
        raw = @extraction.pages
        unless raw.is_a?(Array) && raw.any?
          error!(:pages_blank)
          return []
        end
        error!(:too_many_pages, count: Extraction::MAX_PAGES) if raw.size > Extraction::MAX_PAGES

        heads = raw.each_with_index.filter_map { |page, index| head_for(page, index) }
        assign_home!(heads)
        heads.each { |head| head.slug = slug_for(head) }
        @known_slugs = existing_slugs | heads.filter_map { |head| link_slug(head) }
        heads.map { |head| page_for(head) }
      end

      def head_for(page, index)
        unless page.is_a?(Hash)
          error!(:page_not_object, index: index + 1)
          return nil
        end

        title = scalar(page["title"]).to_s
        error!(:title_blank, index: index + 1) if title.blank?
        label = title.presence || I18n.t("ai_assistant.assistant.website.page_label", index: index + 1)
        Head.new(source: page, title: title, label: label, record: target_record(page))
      end

      def target_record(page)
        raw_id = page["page_id"]
        return nil if raw_id.blank?

        id = Integer(raw_id.to_s, 10, exception: false)
        record = id && pages_by_id[id]
        return error!(:page_not_found, id: raw_id) unless record
        return error!(:duplicate_page, id: id) if @seen_page_ids.include?(id)

        @seen_page_ids << id
        error!(:page_published, title: record.title) if record.published?
        record
      end

      def assign_home!(heads)
        needs_home = @website.home_page.nil?
        heads.each do |head|
          if head.record
            head.home = head.record.home?
          else
            head.home = needs_home
            needs_home = false
          end
        end
      end

      def slug_for(head)
        return nil if head.home

        slug = scalar(head.source["slug"])
        return nil if slug.blank?
        return error!(:invalid_slug, title: head.label, slug: slug) unless slug.match?(Websites::Contracts::Page::SLUG_FORMAT)
        return error!(:duplicate_slug, slug: slug) if @seen_slugs.include?(slug)
        return error!(:slug_taken, title: head.label, slug: slug) if slug_taken?(slug, head.record)

        @seen_slugs << slug
        slug
      end

      def slug_taken?(slug, record)
        website_pages.any? { |page| page.slug == slug && page != record }
      end

      # The slug an internal href can use to reach this page once it is saved.
      def link_slug(head)
        return nil if head.home
        return head.slug if head.slug
        return head.record.slug.presence if head.record

        head.title.parameterize.presence
      end

      def page_for(head)
        {
          "page_id" => head.record&.id,
          "title" => head.title,
          "slug" => head.slug,
          "nav_visible" => nav_visible(head.source["nav_visible"]),
          "home" => head.home,
          "sections" => sections_for(head)
        }
      end

      def nav_visible(value)
        cast = BOOLEAN.cast(value)
        cast.nil? ? true : cast
      end

      def sections_for(head)
        raw = head.source["sections"]
        unless raw.is_a?(Array) && raw.any?
          error!(:sections_blank, title: head.label)
          return []
        end
        if raw.size > Extraction::MAX_SECTIONS
          error!(:too_many_sections, title: head.label, count: Extraction::MAX_SECTIONS)
        end

        raw.each_with_index.filter_map { |section, index| section_for(section, index, head.label) }
      end

      def section_for(section, index, title)
        unless section.is_a?(Hash)
          error!(:section_not_object, title: title, index: index + 1)
          return nil
        end

        type = section["type"].to_s
        unless Websites::SectionKit.known?(type)
          error!(:unknown_section, title: title, index: index + 1, type: type)
          return nil
        end

        before = @errors.size
        props = fields_for(Websites::SectionFields.full_schema_for(type), section["props"], { title: title, type: type }, "")
        source_props = section["props"].is_a?(Hash) ? section["props"] : {}
        styles = Websites::SectionStyles.sanitize(type, source_props[Websites::SectionStyles::PROP])
        props[Websites::SectionStyles::PROP] = styles if styles.any?
        # The normalizer already reports the precise field/count/option error.
        # Only valid normalized sections need the drift-detection safety net.
        contract_check(type, props, title) if @errors.size == before
        { "type" => type, "props" => props }
      end

      def fields_for(schema, source, context, prefix)
        source = {} unless source.is_a?(Hash)
        schema.each_with_object({}) do |field, props|
          key = field[:key]
          value = field_value(field, source[key], context, "#{prefix}#{key}")
          props[key] = value unless value.nil?
        end
      end

      def field_value(field, value, context, path)
        case field[:kind]
        when :array then array_items(field, value, context, path)
        when :select then option(field, value, context, path)
        else text_value(field, value, context, path)
        end
      end

      def text_value(field, value, context, path)
        text = scalar(value, joiner: field[:kind] == :textarea ? "\n" : ", ")
        return nil if text.blank?
        return nil if Websites::SectionKit::HREF_KEYS.include?(field[:key]) && !valid_href?(text, context, path)
        return nil if Websites::SectionKit::IMAGE_KEYS.include?(field[:key]) && !valid_image?(text, context, path)

        text
      end

      def option(field, value, context, path)
        text = scalar(value)
        return nil if text.blank?
        return text if field[:options].include?(text)

        error!(:invalid_option, **context, field: path, options: field[:options].join(", "))
      end

      def array_items(field, value, context, path)
        min, max = field.values_at(:min, :max)
        if value.nil?
          error!(:array_count, **context, field: path, min: min, max: max) if min.positive?
          return nil
        end
        unless value.is_a?(Array) && value.all?(Hash)
          return error!(:item_not_object, **context, field: path)
        end

        error!(:array_count, **context, field: path, min: min, max: max) unless value.size.between?(min, max)
        value.each_with_index.map do |item, index|
          fields_for(field[:item_fields], item, context, "#{path}[#{index + 1}].")
        end
      end

      def valid_href?(value, context, path)
        if (message = Websites::Href.error_message(value))
          error!(:invalid_href, **context, field: path, message: message)
        elsif value.match?(Websites::Href::SLUG) && @known_slugs.exclude?(value)
          error!(:unknown_link, **context, field: path, slug: value)
        else
          return true
        end
        false
      end

      def valid_image?(value, context, path)
        if Uploads.token?(value)
          return true if @uploads.find(value)

          error!(:unknown_upload, **context, field: path, token: value)
        else
          return true if existing_images.include?(value)

          error!(:invalid_image, **context, field: path)
        end
        false
      end

      # Safety net: the checks above cover everything the contract enforces,
      # so this only fires if the two drift apart.
      def contract_check(type, props, title)
        form = Websites::Contracts::Section.new(SectionModel.new(nil, type, props))
        return if form.validate("type" => type, "props" => props)

        error!(:save_failed, title: title, details: form.errors.full_messages.join(I18n.t("ai_assistant.assistant.website.detail_separator")))
      end

      def scalar(value, joiner: ", ")
        case value
        when String then value.strip
        when Numeric, true, false then value.to_s
        when Array
          value.filter_map { |item| item.to_s.strip.presence if item.is_a?(String) || item.is_a?(Numeric) }.join(joiner)
        end
      end

      def unplaced_in(pages)
        placed = self.class.image_values(pages).to_set
        @uploads.pending.reject { |upload| placed.include?(upload.token) }
      end

      # Queried fresh rather than through the cached association, so a write
      # rolled back in an earlier repair round leaves no phantom pages here.
      def website_pages
        @website_pages ||= @website.pages.where(customer_id: @website.customer_id).to_a
      end

      def pages_by_id
        @pages_by_id ||= website_pages.index_by(&:id)
      end

      def existing_slugs
        website_pages.map(&:slug).reject(&:blank?)
      end

      def existing_images
        @existing_images ||= self.class.image_values(website_pages.map(&:sections)).to_set
      end

      def error!(key, **options)
        @errors << I18n.t("ai_assistant.assistant.website.errors.#{key}", **options) if @errors.size < MAX_ERRORS
        nil
      end
    end
  end
end
