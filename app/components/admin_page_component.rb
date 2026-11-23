# frozen_string_literal: true

# AdminPageComponent
#
# Unified shell for every admin sub-item page (index, show, custom listings).
# Renders the breadcrumbs, the title strip with description and primary/secondary
# action buttons, and yields the body. Flash alerts are rendered once by the
# dashboard layout (the single source of truth), so this component does not
# render them. The page-level width is set via `content_for :container_width`
# so the dashboard layout picks it up — views don't need to handle width
# themselves.
class AdminPageComponent < ApplicationComponent
  ICONS = {
    plus:    "M12 4v16m8-8H4",
    trash:   "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16",
    refresh: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
    download: "M4 16v2a2 2 0 002 2h12a2 2 0 002-2v-2M7 10l5 5 5-5M12 15V3",
    edit:    "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z",
    back:    "M10 19l-7-7m0 0l7-7m-7 7h18",
    shield_check: "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
    settings: "M10.5 6h9.75M10.5 6a1.5 1.5 0 11-3 0m3 0a1.5 1.5 0 10-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-9.75 0h9.75"
  }.freeze

  attr_reader :breadcrumbs, :title, :description, :actions, :width,
              :badges, :icon_path, :icon_class

  # `badges` are `{ label:, variant: }` hashes rendered inline after the title
  # (module status, environment, …). `icon_path`/`icon_class` opt a page into a
  # tinted identity tile left of the title — used where a page represents one
  # of a set of sibling entities (a feature module, a vendor) and the icon is
  # what makes it recognisable at a glance. `wrap_title` keeps long record
  # names on multiple lines instead of truncating them.
  def initialize(breadcrumbs:, title: nil, description: nil, actions: [], width: nil,
                 badges: [], icon_path: nil, icon_class: nil, wrap_title: false, wrap_actions: false)
    @breadcrumbs  = Array(breadcrumbs)
    @title        = title
    @description  = description
    @actions      = Array(actions)
    @width        = width
    @badges       = Array(badges).compact
    @icon_path    = icon_path
    @icon_class   = icon_class.presence || "bg-surface-active text-text-secondary"
    @wrap_title   = wrap_title
    @wrap_actions = wrap_actions
  end

  def has_title?       = title.present?
  def has_actions?     = actions.any?
  def has_description? = description.present?
  def has_badges?      = badges.any?
  def has_icon?        = icon_path.present?
  def edge?            = width.to_s == "edge"

  # Whether the title/actions strip should render at all. Breadcrumb-only pages
  # (no title and no actions) skip the strip entirely.
  def has_header_strip? = has_title? || has_actions?
  def wrap_title? = @wrap_title

  def header_classes
    classes = if @wrap_actions
      "flex flex-col gap-4 lg:flex-row lg:flex-wrap lg:items-start lg:justify-between"
    else
      "flex flex-col gap-2 sm:flex-row #{wrap_title? ? 'sm:items-start' : 'sm:items-center'} sm:justify-between"
    end
    classes += " mb-6 gap-4" unless edge?
    classes
  end

  def action_classes
    if @wrap_actions
      "flex w-full max-w-full flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center lg:w-auto"
    else
      "flex max-w-full flex-wrap items-center gap-2 sm:flex-nowrap"
    end
  end

  def title_classes
    if wrap_title?
      "text-subtitle min-w-0 max-w-full whitespace-normal break-words [overflow-wrap:anywhere]"
    else
      "text-subtitle truncate"
    end
  end

  # Header actions are links unless `method:` is set, in which case the shell
  # renders a real form submit (delete, and similar) with the same button chrome.
  def method_action?(action) = action[:method].present?

  def method_action_attributes(action)
    options = {
      variant: action[:variant] || :secondary,
      size: action[:size] || :sm,
      tag: :button,
      type: "submit"
    }
    options[:class] = action[:class] if action[:class]
    options[:data] = action[:data] if action[:data]
    ButtonComponent.new(**options).html_attributes
  end

  def badge_variant(badge) = (badge[:variant] || :default).to_sym

  def action_icon_path(key)
    return nil if key.nil?
    ICONS[key.to_sym]
  end

  # Map an action hash to ButtonComponent kwargs. An action with :form renders
  # a submit button bound to that form id (for page headers whose primary
  # action saves a form rendered in the page body); otherwise it renders a link.
  def button_kwargs_for(action)
    base = {
      variant: action[:variant] || :secondary,
      size:    action[:size] || :sm,
      data:    action[:data],
      target:  action[:target],
      rel:     action[:rel],
      class:   action[:class]
    }.compact

    if action[:form]
      base.merge(tag: :button, type: "submit", form: action[:form])
    else
      base.merge(tag: :a, href: action[:path])
    end
  end

  def before_render
    helpers.content_for(:container_width, width.to_s) if width
    return if title.blank? || helpers.content_for?(:title)

    helpers.content_for(:title, helpers.strip_tags(title.to_s).squish)
  end
end
