# frozen_string_literal: true

module Billing
  module Admin
    # Label / value rows for read-only billing records (plan, coupon, settings,
    # subscription). Stacks on mobile; label column + value column from sm.
    #
    #   render Billing::Admin::DetailListComponent.new do |list|
    #     list.with_row(label: t("..."), hint: t("...")) { value }
    #   end
    class DetailListComponent < ApplicationComponent
      renders_many :rows, "Billing::Admin::DetailListComponent::Row"

      def call
        tag.dl(safe_join(rows), class: "divide-y divide-border-subtle")
      end

      def render? = rows?

      class Row < ApplicationComponent
        def initialize(label:, hint: nil, mono: false)
          @label, @hint, @mono = label, hint, mono
        end

        def call
          tag.div(class: "grid min-w-0 gap-1 py-3 first:pt-0 last:pb-0 sm:grid-cols-3 sm:gap-6") do
            safe_join([term, tag.dd(content, class: value_classes)])
          end
        end

        private

        def term
          tag.dt(class: "min-w-0") do
            safe_join([tag.span(@label, class: "block text-body-sm font-medium text-text-secondary"),
                       (tag.span(@hint, class: "mt-0.5 block text-caption") if @hint.present?)].compact)
          end
        end

        def value_classes
          ["min-w-0 break-words text-body-sm text-text-primary sm:col-span-2", ("font-mono" if @mono)].compact.join(" ")
        end
      end
    end
  end
end
