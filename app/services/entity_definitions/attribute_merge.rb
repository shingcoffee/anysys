# frozen_string_literal: true

module EntityDefinitions
  # How an incoming attribute list is laid over a stored one.
  #
  # Persist merges definitions key-wise and never deletes, and the assistant's
  # change plan has to predict exactly what that merge will produce. Both sides
  # share these two methods so "what changed" and "what was merged onto" can
  # never drift apart.
  module AttributeMerge
    module_function

    # The identity an attribute is matched on: its slug, or the slug its name
    # would produce. A non-Hash has no identity and collapses to "".
    def attribute_key(attr)
      return "" unless attr.is_a?(Hash)

      attr["name_slug"].to_s.strip.presence || EntityEntry.attribute_slug_for(attr["name"].to_s.strip)
    end

    # Incoming attributes are merged onto their stored twin — keys the caller
    # omitted keep their stored values. Stored attributes keep their order and
    # genuinely new ones are appended.
    def merge_attributes(existing, incoming)
      existing = Array(existing)
      incoming = Array(incoming)
      return incoming if existing.empty?
      return existing if incoming.empty?

      overlay = {}
      existing.each { |attr| overlay[attribute_key(attr)] = attr }
      incoming.each do |attr|
        key = attribute_key(attr)
        current = overlay[key]
        overlay[key] = current.is_a?(Hash) ? current.merge(attr) : attr
      end

      existing_keys = existing.map { |attr| attribute_key(attr) }
      existing_keys.map { |key| overlay[key] } + incoming.reject { |attr| existing_keys.include?(attribute_key(attr)) }
    end
  end
end
