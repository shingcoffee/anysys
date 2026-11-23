# frozen_string_literal: true

module ApplicationHelper
  include ValidatorRegistry
  include ValidatorDisplayHelper

  # Maps a Rails flash key to an AlertComponent type. `notice` is success-styled,
  # `alert`/`error` are error-styled; `warning`/`info` map to themselves and any
  # other key falls back to an informational alert.
  def flash_alert_type(key)
    case key.to_s
    when "notice", "success" then :success
    when "alert", "error"    then :error
    when "warning"           then :warning
    else                          :info
    end
  end

  # Format a timestamp with the current locale's long time format.
  def format_datetime(datetime)
    return "-" if datetime.blank?

    datetime.respond_to?(:strftime) ? I18n.l(datetime, format: :long) : datetime.to_s
  end

  # Format a date with the current locale's long date format.
  def format_date(datetime)
    return "-" if datetime.blank?

    datetime.respond_to?(:to_date) ? I18n.l(datetime.to_date, format: :long) : datetime.to_s
  end

  # Generate a link to an entity by ID, name, or object
  def link_to_entity(entity_or_id, customer_id, link_text: nil)
    if entity_or_id.is_a?(Entity)
      entity = entity_or_id
    else
      entity = Entity.where(customer_id: customer_id)
                     .where("id = ? OR name = ?", entity_or_id.to_s, entity_or_id.to_s)
                     .first
    end

    return content_tag(:span, link_text || entity_or_id.to_s, class: "text-caption text-text-muted") unless entity

    text = link_text || entity.display_label
    link_to text, admin_maintenance_entity_path(customer_id, entity),
            class: "link"
  end

  # Organize entity fields into categorized sections for page builder
  # Delegates to EntityFieldOrganizer service
  def organize_entity_fields(entity)
    EntityFieldOrganizer.call(entity)
  end

  # Returns Tailwind color classes for an HTML type icon (icon color + bg tint).
  def html_type_icon_color(html_type, _fallback_type = nil)
    case html_type.presence
    when "text", "textarea", "search", "password", "hidden", "rich-text", "signature"
      %w[text-slate-500 bg-slate-100/80]
    when "select", "multi-select", "radio", "checkbox", "switch"
      %w[text-violet-500 bg-violet-100/80]
    when "number", "currency", "range", "rating"
      %w[text-blue-500 bg-blue-100/80]
    when "date", "time", "datetime-local", "month", "week"
      %w[text-amber-600 bg-amber-100/80]
    when "email", "tel", "url"
      %w[text-emerald-500 bg-emerald-100/80]
    when "file", "image", "color"
      %w[text-rose-500 bg-rose-100/80]
    else
      %w[text-gray-400 bg-gray-100]
    end
  end

  # Returns SVG path data for an HTML type icon in the page builder sidebar.
  def html_type_icon_path(html_type, _fallback_type = nil)
    case html_type.presence
    when "textarea", "rich-text"
      "M4 6h16M4 10h16M4 14h10"
    when "select", "multi-select", "radio"
      "M8 9l4-4 4 4m0 6l-4 4-4-4"
    when "checkbox", "switch"
      "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
    when "number", "currency", "range", "rating"
      "M7 20l4-16m2 16l4-16M6 9h14M4 15h14"
    when "date", "month", "week"
      "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
    when "time", "datetime-local"
      "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
    when "email"
      "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
    when "tel"
      "M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"
    when "url"
      "M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
    when "file"
      "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"
    when "image"
      "M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z"
    when "color"
      "M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"
    when "signature"
      "M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
    when "password"
      "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
    when "hidden"
      "M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.878 9.878L3 3m6.878 6.878L21 21"
    when "search"
      "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
    else
      "M4 6h16M4 10h16M4 14h16M4 18h16"
    end
  end
end
