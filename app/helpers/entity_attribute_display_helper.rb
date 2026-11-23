# frozen_string_literal: true

# Helpers for rendering entity attribute fields (visibility, display label,
# etc.) in admin views. Mirrors the badge styling that
# template_builder.js#buildVisibilityBadgesHtml renders client-side, so the
# server-rendered table and the JS-appended rows look identical.
module EntityAttributeDisplayHelper
  VISIBILITY_AUDIENCES = %i[admin member public].freeze

  ENABLED_BADGE_CLASS = "badge badge-accent px-1.5 py-0.5 text-xs"
  DISABLED_BADGE_CLASS = "badge badge-default px-1.5 py-0.5 text-xs line-through opacity-50"

  def normalize_attribute_visibility(visibility)
    v = visibility.is_a?(Hash) ? visibility : {}
    {
      admin: v["admin"] != false && v[:admin] != false,
      member: v["member"] != false && v[:member] != false,
      public: v["public"] != false && v[:public] != false
    }
  end

  def render_attribute_visibility_badges(visibility)
    normalized = normalize_attribute_visibility(visibility)
    badges = VISIBILITY_AUDIENCES.map do |key|
      label = I18n.t("comp_admin.attribute_modal.#{key}")
      css = normalized[key] ? ENABLED_BADGE_CLASS : DISABLED_BADGE_CLASS
      content_tag(:span, label, class: css)
    end
    content_tag(:div, safe_join(badges), class: "flex flex-wrap items-center gap-1")
  end
end
