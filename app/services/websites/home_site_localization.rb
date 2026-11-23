# frozen_string_literal: true

module Websites
  # Public-only, read-only presentation of source copy. Literal owner edits stay
  # literal; routes, structure and publication always come from the saved rows.
  class HomeSiteLocalization
    TEXT_KEYS = %w[name tagline title description blurb heading label eyebrow headline
                   subhead kicker body prompt example_label prompt_label output_label
                   review_note status primary_label secondary_label button_label
                   featured_label price cadence features question answer value
                   column_1 column_2 column_3 column_4 value_1 value_2 value_3 value_4].freeze

    def initialize(locale: I18n.locale)
      @locale = locale.to_s
    end

    def website(record)
      return record unless eligible?(record)

      present(record, record.attributes.slice("name", "tagline", "seo", "footer"),
              dictionary([[english.except("pages"), chinese.except("pages")]]))
    end

    def page(record)
      return record unless eligible?(record)

      en = english.fetch("pages").find { |page| page["slug"] == record.slug }
      zh = chinese.fetch("pages").find { |page| page["slug"] == record.slug }
      return record unless en && zh

      copy = present(record, { "title" => record.title }, dictionary([[en.slice("title"), zh.slice("title")]]))
      copy.sections = record.sections.deep_dup.map do |section|
        next section unless section.is_a?(Hash)

        pairs = en.fetch("sections").zip(zh.fetch("sections")).select do |base, _|
          base["type"] == section["type"]
        end
        # Source ids survive reorder. Older restored sites retain sec_* ids, so
        # fall back to unambiguous text within this page and section type only.
        exact = pairs.select { |base, _| base["id"] == section["id"] }
        pairs = exact if exact.any?
        translations = dictionary(pairs.map { |base, target| [base["props"], target["props"]] })
        section.merge("props" => translate(section["props"], translations))
      end
      copy
    end

    private

    def eligible?(record)
      record.customer_id == HomeSite::CUSTOMER_ID && %w[en zh-CN].include?(@locale)
    end

    def english
      @english ||= HomeSite.definition(locale: :en)
    end

    def chinese
      @chinese ||= HomeSite.definition(locale: :"zh-CN")
    end

    def present(record, attributes, translations)
      record.dup.tap do |copy|
        copy.id = record.id
        copy.assign_attributes(translate(attributes, translations))
        copy.readonly!
      end
    end

    def dictionary(pairs)
      candidates = Hash.new { |hash, key| hash[key] = [] }
      pairs.each { |en, zh| collect(en, zh, [], candidates) }
      candidates.filter_map { |key, values| [key, values.first] if values.uniq.one? }.to_h
    end

    def collect(en, zh, path, candidates)
      case en
      when Hash
        return unless zh.is_a?(Hash)

        en.each { |key, value| collect(value, zh[key], path + [key], candidates) if zh.key?(key) }
      when Array
        return unless zh.is_a?(Array)

        en.zip(zh).each { |base, target| collect(base, target, path, candidates) }
      when String
        return unless zh.is_a?(String) && TEXT_KEYS.include?(path.last)

        target = @locale == "zh-CN" ? zh : en
        [en, zh].each { |base| candidates[[path, base]] << target }
      end
    end

    def translate(value, translations, path = [])
      case value
      when Hash
        value.to_h { |key, item| [key, translate(item, translations, path + [key])] }
      when Array
        value.map { |item| translate(item, translations, path) }
      when String
        translations.fetch([path, value], value).dup
      else
        value.deep_dup
      end
    end
  end
end
