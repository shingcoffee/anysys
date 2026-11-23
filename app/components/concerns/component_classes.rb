# frozen_string_literal: true

module ComponentClasses
  # Buttons - prefer using "btn btn-*" classes from the design system
  BTN_PRIMARY = "btn btn-primary"
  BTN_SECONDARY = "btn btn-secondary"
  BTN_GHOST = "btn btn-ghost"
  BTN_DANGER = "btn btn-danger"
  BTN_SUCCESS = "btn btn-success"

  BTN_ICON = "p-2 text-gray-500 rounded-lg hover:bg-gray-100 hover:text-gray-700 " \
             "transition-all duration-200 focus:ring-2 focus:ring-gray-300"

  BTN_SM = "px-2 py-1 text-xs font-medium rounded-md transition-colors"

  # Cards
  CARD = "bg-white border border-gray-200 rounded-lg shadow-sm"

  CARD_HOVER = "bg-white border border-gray-200 rounded-lg shadow-sm " \
               "hover:border-indigo-300 hover:shadow-md transition-all duration-200 cursor-pointer"

  CARD_SELECTED = "bg-indigo-50 border-2 border-indigo-500 rounded-lg shadow-sm"

  # Inputs
  INPUT = "w-full px-3 py-2 border border-gray-300 rounded-lg " \
          "focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 " \
          "transition-all duration-150 placeholder-gray-400"

  INPUT_ERROR = "w-full px-3 py-2 border border-red-300 rounded-lg " \
                "focus:ring-2 focus:ring-red-500 focus:border-red-500 " \
                "transition-all duration-150 bg-red-50"

  INPUT_SM = "w-full px-3 py-2 text-sm border border-gray-300 rounded-md " \
             "shadow-sm placeholder:text-gray-400 focus:outline-none " \
             "focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"

  # Floating panel
  FLOATING_PANEL = "absolute bg-white border border-gray-200 rounded-xl shadow-xl " \
                   "p-4 z-50 min-w-80 animate-fade-in"

  # Labels
  LABEL = "block text-sm font-medium text-gray-700 mb-1"

  LABEL_SM = "block text-xs font-medium text-gray-700 mb-1.5"

  # Help text
  HELP_TEXT = "mt-1 text-sm text-gray-500"

  # Badges
  BADGE = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
  BADGE_PRIMARY = "#{BADGE} bg-indigo-100 text-indigo-800"
  BADGE_SECONDARY = "#{BADGE} bg-gray-100 text-gray-800"
  BADGE_SUCCESS = "#{BADGE} bg-green-100 text-green-800"

  # Dropdowns
  DROPDOWN = "absolute right-0 mt-2 w-56 rounded-lg bg-white shadow-lg " \
             "ring-1 ring-black ring-opacity-5 z-50 animate-fade-in"

  DROPDOWN_ITEM = "block w-full px-4 py-2 text-left text-sm text-gray-700 " \
                  "hover:bg-gray-100 transition-colors duration-150"

  # Sidebar
  SIDEBAR = "bg-white border-l border-gray-200 flex-shrink-0"
  SIDEBAR_HEADER = "flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-gray-50"
  SIDEBAR_BODY = "flex-1 overflow-y-auto p-4 space-y-4"
  SIDEBAR_FOOTER = "flex items-center justify-between gap-2 px-4 py-3 border-t border-gray-200 bg-gray-50"

  # Sections
  SECTION_HEADER = "w-full flex items-center justify-between px-4 py-3 hover:bg-gray-50 transition-colors text-left"
  SECTION_TITLE = "text-xs font-semibold text-gray-500 uppercase tracking-wider"

  # Close button
  CLOSE_BTN = "text-gray-400 hover:text-gray-600 p-1 rounded hover:bg-gray-100 transition-colors"
end
