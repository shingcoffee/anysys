# frozen_string_literal: true

module Websites
  module Activities
    class SaveSkeleton
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(skeleton:, params:)
        attrs = sanitize(params)
        skeleton.key = attrs[:key] if attrs.key?(:key) && skeleton.new_record?
        skeleton.assign_attributes(attrs.except(:key))
        contract = Contracts::Skeleton.new(skeleton)
        unless contract.validate({})
          contract.errors.each { |error| skeleton.errors.add(error.attribute, error.message) }
          return Result.new(success?: false, model: skeleton, errors: skeleton.errors.full_messages)
        end
        skeleton.pages = skeleton.pages.map do |page|
          page.merge("sections" => Websites::Skeletons.decorate_sections(page.fetch("sections")))
        end
        if skeleton.save
          Websites::Catalog.reset_sync_flag!
          Result.new(success?: true, model: skeleton, errors: [])
        else
          Result.new(success?: false, model: skeleton, errors: skeleton.errors.full_messages)
        end
      end

      def self.sanitize(params)
        h = params.to_h.deep_symbolize_keys
        attrs = h.slice(:key, :name, :description, :position, :archived, :pages, :theme_key)
        attrs[:theme_key] = attrs[:theme_key].to_s.presence if attrs.key?(:theme_key)
        attrs[:pages] = normalize_pages(attrs[:pages]) if attrs.key?(:pages)
        attrs[:archived] = ActiveModel::Type::Boolean.new.cast(attrs[:archived]) if attrs.key?(:archived)
        attrs
      end

      def self.normalize_pages(raw)
        list = case raw
        when String
          JSON.parse(raw)
        when Hash
          return :invalid unless raw.keys.all? { |key| key.to_s.match?(/\A\d+\z/) }

          raw.sort_by { |k, _| k.to_s.to_i }.map { |_, page| page }
        when Array
          raw
        else
          return :invalid
        end
        return :invalid unless list.is_a?(Array)

        list.map do |item|
          next item unless item.is_a?(Hash)

          page = item.deep_stringify_keys
          page["title"] = page["title"].strip if page["title"].is_a?(String)
          page["home"] = normalize_boolean(page.fetch("home", false))
          page["nav_visible"] = normalize_boolean(page.fetch("nav_visible", true))
          json = page.delete("sections_json")
          page["sections"] = parse_page_sections(json.present? ? json : page["sections"])
          page
        end
      rescue JSON::ParserError
        :invalid
      end
      private_class_method :normalize_pages

      def self.parse_page_sections(raw)
        list = case raw
        when String
          JSON.parse(raw)
        when Array
          raw
        else
          return :invalid
        end
        list.is_a?(Array) ? list : :invalid
      rescue JSON::ParserError
        :invalid
      end
      private_class_method :parse_page_sections

      def self.normalize_boolean(value)
        return true if [true, "1", "true"].include?(value)
        return false if [false, "0", "false"].include?(value)

        value
      end
      private_class_method :normalize_boolean
    end
  end
end
