# frozen_string_literal: true

module Entities
  # Display text for an entity's entries as one audience may see it: option
  # labels, referenced records' labels, derived values and yes/no instead of
  # stored codes and ids. Built for a page of entries, it loads their derived
  # values in one query and each reference field's labels in one query.
  class EntryDisplay
    BOOLEAN_TYPES = %w[checkbox switch].freeze

    # Attaches a display to each of the tenant's entries, one per entity, for
    # readers that only see the entry (EntityEntry#display_text).
    def self.prime!(entries, customer_id:, audience:, viewer: nil)
      cid = customer_id.to_i
      Array(entries).grep(EntityEntry).select { |entry| entry.customer_id.to_i == cid }
                    .group_by(&:entity_id).each_value do |group|
        entity = group.first.entity
        next unless entity

        display = new(entity: entity, entries: group, customer_id: cid, audience: audience, viewer: viewer)
        group.each { |entry| entry.prime_display!(display) }
      end
    end

    def initialize(entity:, entries:, customer_id:, audience:, viewer: nil)
      @entries = Array(entries)
      @customer_id = customer_id
      @audience = audience
      @viewer = viewer
      attributes = Array(entity.property_schema_json).grep(Hash)
      attributes = BridgeParticipants.pickers(attributes, customer_id: customer_id) if entity.bridge_entity?
      @attributes = attributes.index_by { |attribute| attribute["name_slug"].to_s }
      @derived_slugs = (entity.computed_fields + entity.calculated_fields).map { |field| field["name_slug"].to_s }.to_set
      @file_slugs = @attributes.select { |_slug, attribute| EntityEntry.file_attribute?(attribute) }.keys.to_set
      @reference_labels = {}
      @option_labels = {}
      DerivedValues.prime!(@entries, customer_id: customer_id) if @derived_slugs.any?
    end

    # Defined for the entries this display was built with. Never raises; an
    # unknown slug shows its stored value, and duplicate labels are never
    # numbered here (only dropdowns number them).
    def text(entry, slug)
      key = slug.to_s
      return file_text(entry, key) if @file_slugs.include?(key)

      derived = @derived_slugs.include?(key)
      value = derived ? entry.derived_values[key] : entry.data_json[key]
      return I18n.t("common.labels.em_dash") if blank?(value)

      attribute = @attributes[key]
      return plain(value) if derived || attribute.nil?

      if ReferenceLabels.reference?(attribute)
        reference_text(key, attribute, value)
      elsif (labels = option_labels(key, attribute)).any?
        Array(value).map { |item| labels.fetch(item.to_s, item.to_s) }.join(", ")
      elsif BOOLEAN_TYPES.include?(attribute["html_type"].to_s)
        I18n.t(ActiveModel::Type::Boolean.new.cast(value) ? "common.labels.yes" : "common.labels.no")
      else
        plain(value)
      end
    end

    # The attachments a File or Image field holds; every entry's are loaded in
    # one query.
    def files(entry, slug)
      return [] unless @file_slugs.include?(slug.to_s)

      file_attachments.fetch([entry.id, slug.to_s], [])
    end

    private

    def file_text(entry, slug)
      names = files(entry, slug).map { |file| file.filename.to_s }
      names.empty? ? I18n.t("common.labels.em_dash") : names.join(", ")
    end

    def file_attachments
      @file_attachments ||= ActiveStorage::Attachment
                            .where(record_type: EntityEntry.polymorphic_name, record_id: @entries.filter_map(&:id), name: @file_slugs.to_a)
                            .includes(:blob).order(:id).group_by { |file| [file.record_id, file.name] }
    end

    def blank?(value)
      value.nil? || value == "" || (value.is_a?(Array) && value.all? { |item| item.nil? || item == "" })
    end

    def plain(value)
      value.is_a?(Array) ? value.map(&:to_s).join(", ") : value.to_s
    end

    # A record that is gone reads "Missing record (#id)"; a display field the
    # audience may not see, or a row outside the viewer's scope, leaves the
    # stored id (no label leak through references).
    def reference_text(slug, attribute, value)
      labels = reference_labels(slug, attribute)
      return plain(value) if labels.nil?

      reference_ids(value).map do |id|
        if labels.key?(id)
          ReferenceLabels.text(labels[id], id)
        elsif scoped_audience?
          id
        else
          ReferenceLabels.missing(id)
        end
      end.join(", ")
    end

    def reference_labels(slug, attribute)
      return @reference_labels[slug] if @reference_labels.key?(slug)

      config = attribute["config"]
      ids = @entries.flat_map { |entry| reference_ids(entry.data_json[slug]) }
      @reference_labels[slug] = ReferenceOptions.new(
        entity_id: config["entity_id"], label_field: config["label_field"],
        customer_id: @customer_id, audience: @audience, viewer: @viewer
      ).labels(ids)
    end

    def scoped_audience?
      @audience.to_s != EntityAttributeAudience::ADMIN
    end

    def reference_ids(value)
      Array(value).map { |id| id.to_s.strip }.reject(&:empty?)
    end

    def option_labels(slug, attribute)
      @option_labels[slug] ||= begin
        config = attribute["config"]
        Array(config.is_a?(Hash) ? config["options"] : nil).each_with_object({}) do |option, labels|
          if option.is_a?(Hash)
            labels[option["value"].to_s] = option["label"].presence&.to_s || option["value"].to_s
          elsif !option.nil?
            labels[option.to_s] = option.to_s
          end
        end
      end
    end
  end
end
