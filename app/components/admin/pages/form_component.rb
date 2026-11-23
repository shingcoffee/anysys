# frozen_string_literal: true

module Admin
  module Pages
    # A launched page's form in the entity entry form's layout: grouped fields
    # (the block) above the entry form's submit / Cancel bar.
    # +frame: true+ renders inside the "+ Add New" dialog's Turbo frame: the
    # form submits into that frame and Cancel closes the dialog.
    # +update: true+ edits an existing entry, so the button saves changes
    # instead of carrying the page's create wording.
    # +extra_action+ is a component rendered beside the submit button.
    class FormComponent < ApplicationComponent
      attr_reader :action, :cancel_path, :extra_action

      def initialize(action:, submit_text: nil, cancel_path: nil, frame: false, update: false, extra_action: nil)
        @action = action
        @submit_text = submit_text
        @cancel_path = cancel_path
        @frame = frame
        @update = update
        @extra_action = extra_action
      end

      def frame? = @frame
      def update? = @update

      def submit_label
        return t("admin_misc.entities.entry_form.update") if update?

        @submit_text.presence || t("admin_misc.entities.entry_form.create")
      end

      def submitting_label = t("admin_misc.entities.entry_form.#{update? ? 'updating' : 'submitting'}")
      def dismiss_action = ("entity-quick-add-dialog#close" if frame?)
      def form_data = frame? ? {} : { turbo_frame: "_top" }
    end
  end
end
