# frozen_string_literal: true

module Websites
  module Activities
    class SaveSite
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      KEYS = %i[name tagline published theme seo footer default_layout_key].freeze

      def self.call(site:, params:)
        attrs = sanitize(params)
        site.assign_attributes(attrs)
        contract = Websites::Contracts::Site.new(site)
        unless contract.validate(attrs.deep_stringify_keys)
          return Result.new(success?: false, model: site, errors: contract.errors.full_messages)
        end

        site.save!
        Result.new(success?: true, model: site, errors: [])
      end

      def self.sanitize(params)
        h = params.to_h.deep_symbolize_keys
        attrs = {}
        KEYS.each { |key| attrs[key] = h[key] if h.key?(key) }
        attrs[:published] = ActiveModel::Type::Boolean.new.cast(attrs[:published]) if attrs.key?(:published)
        if attrs.key?(:default_layout_key)
          key = attrs[:default_layout_key].to_s.presence
          if key.present? && !Websites::Catalog.known_layout?(key)
            attrs.delete(:default_layout_key)
          else
            attrs[:default_layout_key] = key
          end
        end
        attrs[:theme] = normalize_theme(attrs[:theme]) if attrs.key?(:theme)
        attrs[:seo] = stringify_hash(attrs[:seo]).slice("title", "description") if attrs.key?(:seo)
        attrs[:footer] = normalize_footer(attrs[:footer]) if attrs.key?(:footer)
        attrs
      end

      def self.normalize_footer(footer)
        hash = stringify_hash(footer)
        columns = hash["columns"]
        list = case columns
        when Hash
          columns.map { |key, col| stringify_hash(col).merge("_ord" => key.to_i) }
        when Array
          columns.each_with_index.map { |col, index| stringify_hash(col).merge("_ord" => index) }
        else
          []
        end
        list = list.sort_by do |column|
          position = column["position"]
          order = column["_ord"].to_i
          [position.present? ? position.to_i : 10_000 + order, order]
        end
        hash["columns"] = list.filter_map do |column|
          heading = column["heading"].to_s.strip
          links_raw = column["links"]
          links = case links_raw
          when Hash then links_raw.sort_by { |k, _| k.to_i }.map { |_, link| stringify_hash(link) }
          when Array then links_raw.map { |link| stringify_hash(link) }
          else []
          end
          links = links.filter_map do |link|
            label = link["label"].to_s.strip
            url = link["url"].to_s.strip
            next if label.blank? && url.blank?

            { "label" => label, "url" => url }
          end
          next if heading.blank? && links.empty?

          { "heading" => heading, "links" => links }
        end
        hash
      end
      private_class_method :normalize_footer

      def self.normalize_theme(theme)
        hash = stringify_hash(theme)
        normalized = hash.slice(*Websites::Theme::TOKENS)
        normalized["preset"] = hash["preset"].to_s if Websites::ThemePresets.known?(hash["preset"])
        normalized
      end
      private_class_method :normalize_theme

      def self.stringify_hash(value)
        value.to_h.deep_stringify_keys
      end
      private_class_method :stringify_hash
    end
  end
end
