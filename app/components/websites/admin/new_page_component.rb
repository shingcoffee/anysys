# frozen_string_literal: true

module Websites
  module Admin
    # New-page body inside the composer form: step one picks a layout, step two
    # names the page and submits. The details card stays in view beside the
    # gallery on wide screens and follows it on narrow ones.
    class NewPageComponent < ApplicationComponent
      STEP_BADGE_CLASS = "flex size-7 shrink-0 items-center justify-center rounded-full bg-accent-subtle text-sm font-semibold tabular-nums text-accent-text"

      def initialize(composer:, form:)
        @composer = composer
        @form = form
      end

      attr_reader :composer, :form

      delegate :layouts, :selected_layout_key, :page, to: :composer

      def layouts?
        layouts.any?
      end

      def picker
        @picker ||= LayoutPickerComponent.new(
          form: form,
          layouts: layouts,
          selected_key: selected_layout_key,
          website: page.try(:website)
        )
      end

      def shell_class
        return "mx-auto w-full max-w-xl" unless layouts?

        "grid min-w-0 grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_20rem] xl:grid-cols-[minmax(0,1fr)_23rem] xl:gap-8"
      end

      def shell_data
        return { new_page_shell: true } unless layouts?

        {
          new_page_shell: true,
          controller: "website-layout-picker",
          action: "change->website-layout-picker#select",
          website_layout_picker_filter_value: picker.initial_filter,
          website_layout_picker_count_formats_value: {
            one: t("website.admin.pages.new.layout_count_template.one"),
            other: t("website.admin.pages.new.layout_count_template.other")
          }.to_json
        }
      end
    end
  end
end
