# frozen_string_literal: true

class ShellComponent < ApplicationComponent
  # Modules, Communication, Entities, Settings, and Maintenance open with the full sidebar.
  # Every other top-menu destination starts collapsed to the icon rail.
  EXPANDED_SIDEBAR_MENU_ITEMS = %i[modules communication entities settings maintenance].freeze

  def initialize(customer:, user:, tree:, menu_items:, current_menu_item:,
                 current_path:, container_width: :wide, settings_printable: false)
    @customer = customer
    @user = user
    @tree = tree
    @menu_items = menu_items || []
    @current_menu_item = current_menu_item
    @current_path = current_path
    @container_width = container_width
    @settings_printable = settings_printable && current_menu_item == :settings
  end

  attr_reader :customer, :user, :tree, :menu_items, :current_menu_item,
              :current_path, :container_width

  def settings_printable? = @settings_printable

  def root_print_classes
    "print:block print:h-auto print:overflow-visible print:bg-white print:[&>*:not([data-shell-workspace])]:hidden" if settings_printable?
  end

  def workspace_print_classes
    "print:block print:h-auto print:overflow-visible print:[&>*:not(main)]:hidden" if settings_printable?
  end

  # Help is reached from the topbar Help menu, not a top-menu tab, so it has
  # no tab to highlight and no sidebar tree.
  def show_sidebar?
    !%i[home assistant help].include?(current_menu_item) && container_width != :edge
  end

  SIDEBAR_COOKIE_PREFIX = "sidebar_state_"

  # The choice is remembered in a session cookie per highlighted top-menu item
  # (written by sidebar_collapsible_controller.js), so the server renders it
  # directly instead of flashing the default on full page loads.
  def sidebar_collapsed?
    return @sidebar_collapsed if defined?(@sidebar_collapsed)

    @sidebar_collapsed = case request.cookies[sidebar_cookie]
                         when "collapsed" then true
                         when "expanded" then false
                         else !EXPANDED_SIDEBAR_MENU_ITEMS.include?(active_menu_key)
                         end
  end

  def sidebar_state
    sidebar_collapsed? ? "collapsed" : "expanded"
  end

  def sidebar_cookie
    "#{SIDEBAR_COOKIE_PREFIX}#{active_menu_key}"
  end

  # The wrapper owns the animated width: the icon rail when collapsed, the
  # sidebar's own breakpoint widths when expanded.
  def sidebar_classes
    "group/sidebar relative hidden min-h-0 shrink-0 transition-[width] duration-200 ease-[cubic-bezier(0.2,0,0,1)] " \
      "motion-reduce:transition-none data-[state=collapsed]:w-[4.25rem] data-[state=collapsed]:md:flex " \
      "#{SidebarComponent.expanded_shell_classes(current_menu_item)}"
  end

  # The full sidebar keeps its width while the wrapper clips it, so its rows
  # slide under the edge instead of reflowing. The outgoing panel fades out
  # quickly; the incoming one eases in, which reads as a crossfade. The hidden
  # panel is `inert` rather than `invisible`: descendants with `transition: all`
  # (e.g. `.icon-button`) would otherwise stay hidden for a frame and refuse
  # the focus the controller moves into the incoming panel.
  def sidebar_full_classes
    "flex h-full min-h-0 shrink-0 transition-opacity duration-200 ease-in motion-reduce:transition-none " \
      "group-data-[state=collapsed]/sidebar:opacity-0 group-data-[state=collapsed]/sidebar:duration-150 " \
      "group-data-[state=collapsed]/sidebar:ease-out"
  end

  def sidebar_rail_classes
    "absolute inset-y-0 left-0 flex w-[4.25rem] flex-col opacity-0 transition-opacity duration-150 ease-out " \
      "motion-reduce:transition-none group-data-[state=collapsed]/sidebar:opacity-100 " \
      "group-data-[state=collapsed]/sidebar:duration-200 group-data-[state=collapsed]/sidebar:ease-in"
  end

  def container_classes
    classes = helpers.container_width_class(container_width)
    settings_printable? ? "#{classes} print:w-full print:max-w-none print:px-0 print:py-0 print:[&>[role=alert]]:hidden" : classes
  end

  def main_classes
    classes = if container_width == :edge
                "relative flex flex-1 min-h-0 flex-col overflow-hidden bg-canvas"
              else
                "relative flex-1 min-h-0 overflow-auto bg-canvas"
              end
    settings_printable? ? "#{classes} print:block print:h-auto print:overflow-visible print:bg-white" : classes
  end

  private

  # Same match MenuBarComponent uses to highlight a top-menu item. Users,
  # Payments, and Communication share the modules sidebar tree, so the
  # highlighted item — not the sidebar contributor — decides the default.
  def active_menu_key
    menu_items.find { |item| item.active_for?(customer, current_path.to_s) }&.key || current_menu_item
  end
end
