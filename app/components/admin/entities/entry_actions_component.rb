# frozen_string_literal: true

module Admin
  module Entities
    # The submit / Cancel bar under an entry form. Cancel runs +dismiss_action+
    # when given, links to +cancel_path+ otherwise, and is left out without either.
    # +extra_action+ is a component rendered beside the submit button.
    class EntryActionsComponent < ApplicationComponent
      attr_reader :submit_label, :submitting_label, :dismiss_action, :cancel_path, :extra_action

      def initialize(submit_label:, submitting_label:, disabled: false, dismiss_action: nil, cancel_path: nil, extra_action: nil)
        @submit_label = submit_label
        @submitting_label = submitting_label
        @disabled = disabled
        @dismiss_action = dismiss_action
        @cancel_path = cancel_path
        @extra_action = extra_action
      end

      def disabled? = @disabled
    end
  end
end
