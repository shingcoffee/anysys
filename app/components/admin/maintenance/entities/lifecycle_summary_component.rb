# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Read-only summary of the status lifecycle on a choice attribute: how
      # many changes it allows, where a new record starts, and each change
      # with who may make it. Renders nothing when no lifecycle is in force.
      class LifecycleSummaryComponent < ApplicationComponent
        Row = Data.define(:from, :to, :audiences)

        def initialize(attribute:)
          @lifecycle = ::Entities::Lifecycle.from_attribute(attribute) if attribute.is_a?(Hash)
        end

        def render?
          @lifecycle.present?
        end

        def count_label
          t("comp_admin.lifecycle_summary.count", count: @lifecycle.transitions.size)
        end

        def starts_at_label
          t("comp_admin.lifecycle_summary.starts_at", state: @lifecycle.label(@lifecycle.initial))
        end

        def rows
          @lifecycle.transitions.map do |transition|
            Row.new(
              from: @lifecycle.label(transition.from),
              to: @lifecycle.label(transition.to),
              audiences: transition.by.map { |audience| t("comp_admin.lifecycle_summary.audiences.#{audience}") }.to_sentence
            )
          end
        end
      end
    end
  end
end
