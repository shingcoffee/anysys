# frozen_string_literal: true

module Websites
  module HomeSite
    class StoryComponent < SectionComponent
      def render? = present_text?(prop("heading")) || present_text?(prop("body")) || media?
      def media? = valid_media?(prop("image_url"))
      def image_left? = prop("image_side") == "left"
      def contact_note? = variant == :contact_note
      def editorial? = variant == :editorial && page_role == :about
      def padding_class = contact_note? ? "pt-16 pb-6 lg:pt-24 lg:pb-8" : super
      def chips
        return [] if page_role.blank?

        Array(I18n.t("website.home_site.story_chips.#{page_role}", default: [])).grep(String).first(2)
      end
      def lead_paragraph_class = "min-w-0 text-[20px] leading-9 font-medium text-slate-800 text-pretty lg:text-[24px] lg:leading-10"
    end
  end
end
