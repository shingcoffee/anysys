# frozen_string_literal: true

module Billing
  module Admin
    # Settings-style form row: label + hint on the left, control on the right
    # from md up. The block renders the control and its inline error.
    class FieldRowComponent < ApplicationComponent
      def initialize(label:, for_id:, hint: nil)
        @label, @for_id, @hint = label, for_id, hint
      end

      def call
        tag.div(class: "grid min-w-0 gap-2 py-4 first:pt-0 last:pb-0 md:grid-cols-5 md:gap-6") do
          safe_join([
            tag.div(safe_join([tag.label(@label, for: @for_id, class: "form-label mb-0"),
                               (tag.p(@hint, class: "mt-0.5 text-caption") if @hint.present?)].compact),
                    class: "min-w-0 md:col-span-2"),
            tag.div(content, class: "min-w-0 md:col-span-3")
          ])
        end
      end
    end
  end
end
