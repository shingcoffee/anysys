# frozen_string_literal: true

module Admin
  module Entities
    # One bridge row card in AssociationEntriesFormComponent. +index+ is the
    # row's key in rows[<index>] (the ROW_TOKEN placeholder in the template);
    # +number+ is its 1-based position, filled in by the controller when nil.
    class AssociationEntryRowComponent < ApplicationComponent
      attr_reader :form, :index, :number, :quick_adds

      def initialize(form:, index:, number:, heading_template:, quick_adds:, removable:)
        @form = form
        @index = index
        @number = number
        @heading_template = heading_template
        @quick_adds = quick_adds
        @removable = removable
      end

      def removable? = @removable
      def fields = form.groups.flat_map(&:fields)
      def id_prefix = "association_row_#{index}"
      def name_prefix = "rows[#{index}]"
      def heading = number ? @heading_template.sub("{number}", number.to_s) : nil

      # Errors no field of the row displays (e.g. a missing linked record).
      def row_errors
        slugs = fields.map { |field| field.slug.to_s }
        form.errors.reject { |slug, _| slugs.include?(slug.to_s) }.values.flatten.uniq
      end
    end
  end
end
