# frozen_string_literal: true

module Admin
  module Entities
    # One titled group of an entry form: its fields sit in a two-column grid,
    # and every group after the first is set off by a rule.
    class EntryGroupComponent < ApplicationComponent
      attr_reader :description

      def initialize(label:, separated: false, description: nil)
        @label = label
        @separated = separated
        @description = description
      end

      def separated? = @separated
      def label = @label.presence || t("admin_misc.entities.entry_detail.ungrouped")
    end
  end
end
