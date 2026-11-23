# frozen_string_literal: true

module PageShortcuts
  class ManagementComponent < ApplicationComponent
    def initialize(shortcuts:, available_targets:, customer_id:, errors: [], form_values: {}, editing_shortcut: nil)
      @shortcuts = Array(shortcuts).sort_by { |shortcut| shortcut.path.to_s }
      @available_targets = Array(available_targets)
      @customer_id = customer_id
      @errors = errors.respond_to?(:to_hash) ? errors.to_hash.stringify_keys : { "base" => Array(errors) }
      @form_values = form_values.to_h.stringify_keys
      @editing_shortcut = editing_shortcut
    end

    attr_reader :shortcuts, :available_targets, :customer_id, :editing_shortcut

    def index_path
      helpers.admin_maintenance_page_shortcuts_path(customer_id)
    end

    def form_path
      editing_shortcut ? record_path(editing_shortcut) : index_path
    end

    def record_path(shortcut)
      helpers.admin_maintenance_page_shortcut_path(customer_id, shortcut)
    end

    def edit_path(shortcut)
      helpers.admin_maintenance_page_shortcuts_path(customer_id, edit: shortcut.id, anchor: "shortcut-form")
    end

    def form_value(field)
      return @form_values[field.to_s] if @form_values.key?(field.to_s)
      return "" unless editing_shortcut

      field == :path ? editing_shortcut.path : target_value(editing_shortcut)
    end

    def target_options
      options = available_targets.dup
      selected = form_value(:target).to_s
      if selected.present? && options.none? { |_, value| value == selected }
        label = editing_shortcut && selected == target_value(editing_shortcut) ? destination_label(editing_shortcut) : selected
        options << [t("page_shortcuts.unavailable_option", destination: label), selected]
      end
      options
    end

    def field_errors(field)
      Array(@errors[field.to_s]).flatten.compact
    end

    def error_messages
      @errors.values.flatten.compact
    end

    def field_aria(field)
      ids = ["page-shortcut-#{field}-hint"]
      ids << "page-shortcut-#{field}-error" if field_errors(field).any?
      { invalid: field_errors(field).any?, describedby: ids.join(" ") }
    end

    def destination_label(shortcut)
      title = lookup.target_title(shortcut.target_type, shortcut.target_id)
      return t("page_shortcuts.missing_destination") if title.nil?

      title = title.presence || t("page_shortcuts.untitled_destination")
      type_key = shortcut.target_type == "WebsitePage" ? "website_page" : "public_page"
      t("page_shortcuts.destination_label", type: t("page_shortcuts.target_types.#{type_key}"), title: title)
    end

    def available?(shortcut)
      lookup.shortcut_available?(shortcut)
    end

    def public_path(shortcut)
      @public_paths ||= {}
      @public_paths[shortcut.id] ||= Current.set(page_shortcuts_lookup: lookup) do
        helpers.page_shortcuts_mounted_path(PublicPath.shortcut(shortcut: shortcut, host: helpers.request.host)) || shortcut.path
      end
    end

    private

    def lookup
      @lookup ||= Lookup.new(customer_id: PathPolicy.customer_id(customer_id), host: helpers.request.host, include_titles: true)
    end

    def target_value(shortcut)
      "#{shortcut.target_type}:#{shortcut.target_id}"
    end
  end
end
