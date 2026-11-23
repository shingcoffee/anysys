# frozen_string_literal: true

module Pages
  module Submission
    # What a page submission may hand its flowchart, from one permit pass:
    # the page's own fields (conditional rules applied) and bridge sections
    # through Pages::FormParams, ownership through Pages::AudienceGuard, and the
    # locked inputs (+bindings+, resolved and re-checked by
    # Pages::InputBindings) over anything posted for them. On +create+, what
    # the visitor cannot set starts at the definition's defaults.
    class Input
      attr_reader :values, :sections, :identity, :error

      def self.permit(page:, entity:, params:, bindings:, audience:, viewer:, customer_id:, create: false)
        form = FormParams.new(page: page, entity: entity, params: params, audience: audience)
        primary, sections = form.permit_parts
        primary = primary.except(*bindings.to_h.keys.map(&:to_s))
        guarded = AudienceGuard.call(entity: entity, primary: primary, sections: sections, viewer: viewer,
                                     audience: audience, customer_id: customer_id)
        new(page: page, entity: entity, guarded: guarded, identity: form.permit_identity, bindings: bindings,
            starting: create ? form.starting_values : {})
      end

      def initialize(page:, entity:, guarded:, identity:, bindings:, starting: {})
        @page = page
        @entity = entity
        @typed = guarded.primary
        @values = starting.merge(guarded.primary).merge(bindings.to_h.stringify_keys)
        @sections = guarded.sections
        @identity = identity.to_h
        @error = guarded.error
      end

      def rejected? = !@error.nil?

      # What the submitter typed, to show again after a refusal; a password
      # never is.
      def retry_values
        @typed.except(*password_slugs).select { |_slug, value| value.is_a?(String) }
      end

      private

      def password_slugs
        fields = Page.input_fields_in(@page.configuration_json).map { |field| [field["property_slug"], field["html_type"]] }
        attributes = Array(@entity.property_schema_json).grep(Hash).map { |item| [item["name_slug"], item["html_type"]] }
        (fields + attributes).select { |_slug, type| type == "password" }.map { |slug, _type| slug.to_s }
      end
    end
  end
end
