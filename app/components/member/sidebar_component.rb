# frozen_string_literal: true

module Member
  # Icon catalog for member-surface settings. The portal itself is the
  # site-style top bar on Member::ShellComponent.
  class SidebarComponent
    ICON_PATHS = {
      home:          "M3 10.5L12 3l9 7.5M5 9.5V21h5v-6h4v6h5V9.5",
      document_text: "M9 12h6m-6 4h6M7 3h7l5 5v13a1 1 0 01-1 1H7a1 1 0 01-1-1V4a1 1 0 011-1z",
      credit_card:   "M2 8h20M2 12h20M5 6h14a3 3 0 013 3v6a3 3 0 01-3 3H5a3 3 0 01-3-3V9a3 3 0 013-3z",
      user:          "M16 14a4 4 0 10-8 0M12 11a3 3 0 100-6 3 3 0 000 6zM4 21a8 8 0 0116 0",
      shield_check:  "M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3zM9 12l2 2 4-4"
    }.freeze
  end
end
