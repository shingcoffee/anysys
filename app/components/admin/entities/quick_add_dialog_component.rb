# frozen_string_literal: true

module Admin
  module Entities
    # The "+ Add New" modal for entity-backed dropdowns (FormFields::
    # SelectFieldComponent with quick_add), reached as a Stimulus outlet. It
    # loads the referenced entity's Create Entry form into its frame and hands
    # the saved entry back to the dropdown. Levels nest: the form loaded at
    # depth N renders the depth N + 1 dialog for its own reference dropdowns,
    # and each level has its own dialog, frame and title ids.
    class QuickAddDialogComponent < ApplicationComponent
      DIALOG_PREFIX = "entity-quick-add-dialog"
      FRAME_PREFIX  = "entity-quick-add-frame"
      TITLE_PREFIX  = "entity-quick-add-title"
      MAX_DEPTH = 10
      FRAME_PATTERN = /\A#{FRAME_PREFIX}-(\d{1,2})\z/

      def self.dialog_id(depth) = "#{DIALOG_PREFIX}-#{depth}"
      def self.frame_id(depth) = "#{FRAME_PREFIX}-#{depth}"

      # The nesting level a Turbo-Frame request id names, or nil when it is
      # not a quick-add frame.
      def self.depth_of(frame_id)
        depth = frame_id.to_s[FRAME_PATTERN, 1]&.to_i
        depth if depth && depth <= MAX_DEPTH
      end

      # The SelectFieldComponent quick_add config that opens the dialog at
      # +depth+ on +entity+'s Create Entry form, or nil past MAX_DEPTH.
      def self.opener(entity:, customer_id:, label_field:, depth:)
        return if depth > MAX_DEPTH

        {
          url: Rails.application.routes.url_helpers.new_admin_entity_entry_path(
            customer_id, entity, label_field: label_field.to_s.presence
          ),
          label: I18n.t("admin_misc.entities.quick_add.option"),
          title: I18n.t("admin_misc.entities.quick_add.title", name: entity.display_label.presence || entity.name),
          dialog: "##{dialog_id(depth)}"
        }
      end

      attr_reader :depth

      def initialize(depth: 0)
        @depth = depth
      end

      def render? = depth <= MAX_DEPTH

      def dialog_id = self.class.dialog_id(depth)
      def frame_id = self.class.frame_id(depth)
      def title_id = "#{TITLE_PREFIX}-#{depth}"
    end
  end
end
