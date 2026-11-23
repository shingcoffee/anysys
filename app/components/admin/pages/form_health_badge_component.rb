# frozen_string_literal: true

module Admin
  module Pages
    # "Can't be submitted" or "Out of date" beside a form's launch status,
    # with the reason in the tooltip and for screen readers. Renders nothing
    # for a form that needs no badge.
    class FormHealthBadgeComponent < ApplicationComponent
      VARIANTS = { cannot_submit: :danger, out_of_date: :warning }.freeze

      def initialize(status:)
        @status = status
      end

      def render?
        @status.present? && VARIANTS.key?(@status.kind)
      end

      def call
        render(BadgeComponent.new(variant: VARIANTS.fetch(@status.kind), size: :sm, data: { tooltip: hint })) do
          safe_join([label, tag.span(hint, class: "sr-only")], " ")
        end
      end

      private

      def label
        t("admin_misc.pages.#{@status.kind}")
      end

      def hint
        if @status.kind == :cannot_submit
          t("admin_misc.pages.cannot_submit_hint", problems: @status.problems.join("; "))
        else
          t("admin_misc.pages.out_of_date_hint", built: @status.built, entity: @status.entity_name, current: @status.current)
        end
      end
    end
  end
end
