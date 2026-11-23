# frozen_string_literal: true

module Websites
  # Localized nameplates share the native image's center crop. Geometry is in
  # source viewBox units, including the source's outer/inner transform order.
  class IllustrationComponent < PublicComponent
    ILLUSTRATIONS = {
      "/site-images/anysys/anysys-home-workspace-hero.svg" => {
        view_box: "0 0 2400 1030",
        labels: [
          { key: "settings_people.icons.rectangle_stack", transform: "translate(-172 -30.9) scale(1.06)",
            plate: [991, 373, 348, 60], text: [1000, 423, 64], fill: "#FAF9FF", text_fill: "#3C286B" },
          { key: "chrome.sidebar.pages.website", transform: "translate(-172 -30.9) scale(1.06)", inner_transform: "rotate(7 1650 440)",
            plate: [1467, 166, 332, 58], text: [1480, 216, 56], fill: "#FAF9FF", text_fill: "#3C286B", radius: 6 }
        ]
      },
      "/site-images/anysys/anysys-ai-draft.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.home_site.preview.draft", transform: "translate(144 90) scale(.82)", inner_transform: "rotate(3 861 667)",
            plate: [741, 482, 280, 64], text: [750, 541, 80], fill: "#E9DDF9", text_fill: "#3C286B" }
        ]
      },
      "/site-images/anysys/anysys-website-draft.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.home_site.preview.draft", transform: "rotate(-2 806 500)",
            plate: [480, 317, 305, 90], text: [492, 389, 72], fill: "#493481", text_fill: "#FFFFFF" }
        ]
      },
      "/site-images/anysys/anysys-brand-studio.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.platform.catalog.theme.swatches",
            plate: [655, 294, 295, 76], text: [670, 354, 64], fill: "#FAF9FF", text_fill: "#3C286B" }
        ]
      },
      "/site-images/anysys/anysys-review-publish.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "common.labels.preview", transform: "rotate(4 984 535)",
            plate: [707, 369, 325, 80], text: [718, 434, 72], fill: "#493481", text_fill: "#FFFFFF" }
        ]
      },
      "/site-images/anysys/anysys-records-forms.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "settings_people.icons.rectangle_stack", transform: "rotate(-3 704 478)",
            plate: [353, 302, 470, 59], text: [365, 351, 64], fill: "#493481", text_fill: "#FFFFFF" },
          { key: "chrome.menu_bar.items.forms", transform: "rotate(4 1113 555)",
            plate: [1008, 307, 270, 70], text: [1017, 365, 64], fill: "#E9DEF9", text_fill: "#3C286B" }
        ]
      },
      "/site-images/anysys/anysys-members-payments.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "settings_navigation.groups.members", transform: "rotate(-3 716 566)",
            plate: [508, 539, 407, 78], text: [716, 602, 64], fill: "#FAF9FF", text_fill: "#3C286B", anchor: "middle" },
          { key: "chrome.menu_bar.items.payments", transform: "rotate(7 1120 661)",
            plate: [940, 500, 346, 62], text: [953, 548, 64], fill: "#FAF9FF", text_fill: "#3C286B" }
        ]
      },
      "/site-images/anysys/anysys-email-sms.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "chrome.menu_bar.items.email", transform: "rotate(-7 653 500)",
            plate: [511, 342, 338, 73], text: [521, 397, 64], fill: "#EBE1F8", text_fill: "#3C286B" },
          { key: "chrome.menu_bar.items.sms", transform: "rotate(7 1118 471)",
            plate: [1006, 340, 190, 68], text: [1010, 392, 64], fill: "#E7D9F7", text_fill: "#3C286B" }
        ]
      },
      "/site-images/anysys/anysys-local-desktop.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.home_site.illustration.local_data", transform: "matrix(.99 .06 -.08 .99 68 -46)",
            plate: [515, 214, 508, 65], text: [526, 264, 64], fill: "#FAF9FF", text_fill: "#3C286B" }
        ]
      },
      "/site-images/anysys/anysys-record-control.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "settings_people.icons.rectangle_stack",
            plate: [640, 714, 320, 77], text: [800, 768, 64], fill: "#E0AFAD", text_fill: "#64324E", radius: 17, anchor: "middle" }
        ]
      },
      "/site-images/anysys/anysys-local-privacy.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.home_site.illustration.local_data", transform: "translate(-120 -75) scale(1.15)",
            plate: [442, 674, 389, 77], text: [458, 730, 64], fill: "#FAF9FF", text_fill: "#3C286B", radius: 12 }
        ]
      },
      "/site-images/anysys/anysys-platform-workspace-hero.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "settings_people.icons.rectangle_stack", transform: "rotate(2 826 587)",
            plate: [611, 398, 342, 76], text: [620, 461, 72], fill: "#493481", text_fill: "#FFFFFF" }
        ]
      },
      "/site-images/anysys/anysys-pricing-growth-hero.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "settings_navigation.items.plan_subscription", transform: "rotate(-3 621 526)",
            plate: [542, 402, 182, 68], text: [633, 459, 72], fill: "#493481", text_fill: "#FFFFFF", anchor: "middle" }
        ]
      },
      "/site-images/anysys/anysys-about-idea-hero.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.home_site.illustration.idea", transform: "rotate(-6 448 584)",
            plate: [332, 493, 223, 95], text: [344, 559, 72], fill: "#FFE8D9", text_fill: "#64324E" }
        ]
      },
      "/site-images/anysys/anysys-contact-conversation-hero.svg" => {
        view_box: "0 0 1600 1000",
        labels: [
          { key: "website.home_site.illustration.idea", transform: "rotate(-7 533 499)",
            plate: [394, 339, 310, 73], text: [403, 394, 72], fill: "#FFE8D9", text_fill: "#64324E" },
          { key: "website.home_site.illustration.goals", transform: "rotate(6 1091 616)",
            plate: [960, 454, 293, 79], text: [966, 519, 72], fill: "#D9F8ED", text_fill: "#24594F" }
        ]
      }
    }.each_value do |illustration|
      illustration.fetch(:labels).each do |label|
        label.each_value(&:freeze)
        label.freeze
      end.freeze
      illustration.freeze
    end.freeze

    def self.known?(src)
      ILLUSTRATIONS.key?(src)
    end

    def initialize(src:, alt: "", css_class: "", eager: false)
      @src = src
      @alt = alt
      @css_class = css_class
      @eager = eager
      @illustration = ILLUSTRATIONS.fetch(src)
    end

    attr_reader :src, :alt, :illustration

    def frame_class
      classes = @css_class.to_s.split - %w[object-cover]
      # HTML class order cannot override Tailwind's position utilities. Only
      # supply a containing block when the caller has not already supplied one.
      classes.unshift("relative") unless (classes & %w[absolute relative fixed sticky]).any?
      (classes + %w[overflow-hidden]).uniq.join(" ")
    end

    def loading
      @eager ? "eager" : "lazy"
    end
  end
end
