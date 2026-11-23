# frozen_string_literal: true

module Admin
  module Entities
    class EntryFormComponent < ApplicationComponent
      attr_reader :form, :url, :http_method, :cancel_path, :quick_add_depth, :id_prefix

      # +http_method: :patch+ saves an existing entry; :post creates one.
      # +frame: true+ renders inside the quick-add dialog's Turbo frame: the
      # form submits into that frame and Cancel closes the dialog.
      # +quick_add_depth+ is the QuickAddDialogComponent level that reference
      # dropdowns open with "+ Add New"; nil leaves them without it.
      # +id_prefix+ scopes element ids so nested forms on one page never clash.
      # +submit_label+ replaces the Create / Update button text.
      # +dismiss_action+ is the Stimulus action a Cancel button runs, for a
      # page form inside an in-page modal. A page form with neither it nor
      # +cancel_path+ renders no Cancel button.
      def initialize(form:, url:, http_method: :post, cancel_path: nil, frame: false, quick_add_depth: nil, id_prefix: "entry",
                     submit_label: nil, dismiss_action: nil)
        @form = form
        @url = url
        @http_method = http_method
        @cancel_path = cancel_path
        @frame = frame
        @quick_add_depth = quick_add_depth
        @id_prefix = id_prefix
        @submit_label = submit_label
        @dismiss_action = dismiss_action
      end

      def field_id(field) = EntryFieldComponent.field_id(field.slug, id_prefix)
      def errors_heading_id = "#{id_prefix}_errors_heading"

      def frame? = @frame
      def update? = http_method == :patch
      def dismiss_action = frame? ? "entity-quick-add-dialog#close" : @dismiss_action

      def submit_label
        @submit_label.presence || t("admin_misc.entities.entry_form.#{update? ? 'update' : 'create'}")
      end

      def submitting_label
        t("admin_misc.entities.entry_form.#{update? ? 'updating' : 'submitting'}")
      end

      def form_data
        frame? ? {} : { turbo_frame: "_top" }
      end

      def groups
        @groups ||= form.groups.reject { |group| group.fields.empty? }
      end

      def quick_add_for(field)
        quick_adds[field.slug]
      end

      # Rendered after the form: the dialog hosts another entry form.
      def quick_add_dialog?
        quick_adds.any?
      end

      def summary_errors
        fields = groups.flat_map(&:fields).index_by { |field| field.slug.to_s }
        form.errors.flat_map do |slug, messages|
          Array(messages).map { |message| { field: fields[slug.to_s], message: message } }
        end
      end

      def unavailable_message
        if form.blockers.any?
          I18n.t("admin_misc.entities.entry_form.unsupported_fields", fields: form.blockers.map(&:label).join(", "))
        else
          I18n.t("admin_misc.entities.entry_form.no_fields")
        end
      end

      private

      def quick_adds
        @quick_adds ||= if quick_add_depth
          groups.flat_map(&:fields).each_with_object({}) do |field, openers|
            next unless field.html_type == "select" && field.reference&.entity

            opener = QuickAddDialogComponent.opener(entity: field.reference.entity, customer_id: form.customer.id,
                                                    label_field: field.reference.label_field, depth: quick_add_depth)
            openers[field.slug] = opener if opener
          end
        else
          {}
        end
      end
    end
  end
end
