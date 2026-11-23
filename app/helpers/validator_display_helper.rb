# frozen_string_literal: true

# Helpers for rendering validator badges and labels in views.
#
# Delegates label generation to ValidatorRegistry and handles
# both old (string) and new (object with config) formats.
#
module ValidatorDisplayHelper
  def validator_label(validator)
    ValidatorRegistry.validator_label(validator)
  end

  def validator_badge_display_label(validator)
    if validator.is_a?(String)
      validator_label(validator)
    elsif validator.is_a?(Hash) && validator["type"]
      ValidatorRegistry.build_validator_display_label(validator["type"], validator["config"])
    else
      validator.to_s
    end
  end

  def render_validator_badges(validators, truncate: false)
    validators = Array(validators)

    return content_tag(:span, I18n.t("common.labels.em_dash"), class: "text-caption text-text-muted") if validators.empty?

    labels = validators.map { |v| validator_badge_display_label(v) }

    badges = validators.map do |v|
      display_label = validator_badge_display_label(v)
      title_text = if v.is_a?(String)
        v
      elsif v.is_a?(Hash) && v["type"]
        v["type"]
      else
        v.to_s
      end

      opts = {
        class: "badge badge-default border border-border-subtle px-1.5 py-0.5 text-xs shrink-0"
      }
      opts[:title] = title_text unless truncate
      content_tag(:span, display_label, opts)
    end

    inner_class = truncate ? "flex items-center gap-1 flex-nowrap" : "flex items-center gap-1 flex-wrap"
    inner = content_tag(:div, safe_join(badges), class: inner_class)

    return inner unless truncate

    content_tag(:div, inner,
      class: "max-w-[9rem] overflow-hidden cursor-help",
      data: {
        tooltip: labels.join("\n"),
        tooltip_multiline: true,
        tooltip_overflow: true
      },
      aria: { label: labels.join(", ") })
  end
end
