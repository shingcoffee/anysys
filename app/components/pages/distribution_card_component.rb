# frozen_string_literal: true

module Pages
  # Single "Publishing & access" card for the page detail show surface:
  # launch lifecycle + public URL, then independent audience switches, an
  # action key, siblings in the same action, and per-audience Open / URL rows.
  # Visibility changes auto-save via the page-visibility Stimulus controller
  # (independent switches + last-audience lock + form requestSubmit) to
  # admin_maintenance_page_visibility_path with:
  # page[visible_audiences][] and page[action_key].
  class DistributionCardComponent < ViewComponent::Base
    DOT_CLASSES = {
      "admin"  => "bg-accent",
      "member" => "bg-member-accent",
      "public" => "bg-success"
    }.freeze

    SIBLING_BADGE_VARIANTS = {
      "admin"  => :primary,
      "member" => :info,
      "public" => :success
    }.freeze

    def initialize(page:, customer_id:, return_to: nil, turbo_frame: nil, publishing_editable: true)
      @page                = page
      @customer_id         = customer_id
      @return_to           = return_to
      @turbo_frame         = turbo_frame
      @publishing_editable = publishing_editable
    end

    def public_url
      return nil unless page.launched? && page.visible_to?("public") && page.public_uuid

      path = public_path
      "#{helpers.request.base_url}#{path}" if path.present?
    end

    def action_url
      return if page.action_key.blank?

      helpers.page_action_url(customer_id: customer_id, action_key: page.action_key)
    end

    def siblings
      return [] if page.action_key.blank?

      Pages::ActionResolver.siblings(page)
    end

    def audiences_with_rows
      PageVisibility::AUDIENCES.map do |key|
        checked     = page.visible_to?(key)
        last_locked = publishing_editable? && page.visible_audiences == [key]
        enabled     = page.launched? && checked
        open_url    = enabled ? absolute_open_url(key) : nil

        {
          key:              key,
          label:            audience_label(key),
          hint:             I18n.t("comp_misc.distribution.hints.#{key}"),
          dot_class:        DOT_CLASSES[key],
          checked:          checked,
          last_locked:      last_locked,
          switch_disabled:  last_locked || !publishing_editable?,
          switch_aria:      last_locked ? last_audience_reason : audience_label(key),
          enabled:          enabled,
          disabled_reason:  (!page.launched? && checked) ? I18n.t("comp_misc.distribution.not_launched") : nil,
          open_url:         open_url,
          show_url_row:     open_url.present?
        }
      end
    end

    def last_audience_reason
      I18n.t("comp_misc.distribution.last_audience")
    end

    def sibling_badge_variant(key)
      SIBLING_BADGE_VARIANTS.fetch(key)
    end

    def launch_form_options
      opts = {}
      opts[:params] = { return_to: return_to } if return_to.present?
      if turbo_frame.present?
        opts[:form] = { data: { turbo_frame: turbo_frame } }
      end
      opts
    end

    def visibility_form_data
      data = {}
      if publishing_editable?
        data[:controller] = "page-visibility tooltip"
        data[:page_visibility_saving_value] = I18n.t("comp_misc.distribution.saving")
        data[:page_visibility_last_audience_value] = last_audience_reason
      end
      data[:turbo_frame] = turbo_frame if turbo_frame.present?
      data
    end

    def publishing_editable?
      @publishing_editable
    end

    private

    attr_reader :page, :customer_id, :return_to, :turbo_frame

    def audience_label(key)
      I18n.t("comp_misc.distribution.labels.#{key}")
    end

    def absolute_open_url(key)
      path = case key
      when "admin"  then helpers.admin_maintenance_page_render_path(customer_id, page)
      when "member" then helpers.member_page_path(customer_id, page)
      when "public" then public_url
      end
      return if path.blank?

      path.start_with?("http://", "https://") ? path : "#{helpers.request.base_url}#{path}"
    end

    def public_path
      helpers.page_shortcuts_mounted_path(PageShortcuts::PublicPath.public_page(page: page, customer_id: customer_id, host: helpers.request.host))
    end
  end
end
