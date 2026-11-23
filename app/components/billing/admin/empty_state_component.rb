# frozen_string_literal: true

module Billing
  module Admin
    # Borderless empty state for use inside a billing panel or table card.
    class EmptyStateComponent < ApplicationComponent
      renders_one :action

      def initialize(icon:, title:, description: nil)
        @icon, @title, @description = icon, title, description
      end

      def call
        tag.div(class: "flex flex-col items-center gap-3 px-6 py-14 text-center") do
          safe_join([
            tag.span(render(IconComponent.new(name: @icon, class_name: "size-6")),
                     class: "flex size-12 items-center justify-center rounded-xl bg-surface-active text-text-muted"),
            tag.div(safe_join([tag.p(@title, class: "font-medium text-text-primary"),
                               (tag.p(@description, class: "text-body-sm text-text-secondary") if @description.present?)].compact),
                    class: "max-w-sm space-y-1"),
            (tag.div(action, class: "pt-1") if action?)
          ].compact)
        end
      end
    end
  end
end
