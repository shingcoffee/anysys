# frozen_string_literal: true

module Admin
  module Entities
    # Adds one or many bridge rows for one association of a primary entry in a
    # single submit (e.g. several course enrollments with their grades). Each
    # row is a bridge EntryForm posted as rows[<index>][<slug>]; the
    # association-rows controller clones the blank row template to add more.
    class AssociationEntriesFormComponent < ApplicationComponent
      ROW_TOKEN = "__ROW__"

      attr_reader :forms, :template_form, :url, :cancel_path, :errors, :quick_add_depth

      # +template_form+ is a blank row form (the bridge's defaults) for new rows.
      # +frame: true+ renders inside a QuickAddDialogComponent frame: the form
      # submits into it and Cancel closes the dialog. +quick_add_depth+ is the
      # dialog level the target dropdowns' "+ Add New" opens.
      def initialize(forms:, template_form:, url:, cancel_path:, errors: {}, frame: false, quick_add_depth: 0)
        @forms = forms
        @template_form = template_form
        @url = url
        @cancel_path = cancel_path
        @errors = errors.to_h
        @frame = frame
        @quick_add_depth = quick_add_depth
      end

      def frame? = @frame
      def form_data = frame? ? {} : { turbo_frame: "_top" }
      def available? = template_form.available?

      def base_errors = Array(errors["base"])
      def rows_invalid? = forms.any? { |form| form.errors.any? }
      def errors? = base_errors.any? || (available? && rows_invalid?)

      def unavailable_message
        if template_form.blockers.any?
          t("admin_misc.entities.entry_form.unsupported_fields", fields: template_form.blockers.map(&:label).join(", "))
        else
          t("admin_misc.entities.entry_form.no_fields")
        end
      end

      def row(form, index)
        AssociationEntryRowComponent.new(form: form, index: index, number: index.is_a?(Integer) ? index + 1 : nil,
                                         heading_template: heading_template, quick_adds: quick_adds,
                                         removable: forms.size > 1 || !index.is_a?(Integer))
      end

      def template_row = row(template_form, ROW_TOKEN)

      def heading_template = t("admin_misc.entities.association_entries.row_heading", number: "{number}")

      def quick_add_dialog? = quick_adds.any?

      private

      def quick_adds
        @quick_adds ||= template_form.groups.flat_map(&:fields).each_with_object({}) do |field, openers|
          next unless field.html_type == "select" && field.reference&.entity

          opener = QuickAddDialogComponent.opener(entity: field.reference.entity, customer_id: template_form.customer.id,
                                                  label_field: field.reference.label_field, depth: quick_add_depth)
          openers[field.slug] = opener if opener
        end
      end
    end
  end
end
