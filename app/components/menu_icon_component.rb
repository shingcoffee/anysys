# frozen_string_literal: true

# Shared outline icons for the desktop navigation and mobile drawer.
class MenuIconComponent < ApplicationComponent
  PATHS = {
    home: "M3 10.5 12 3l9 7.5M5.25 9v10.5a1.5 1.5 0 0 0 1.5 1.5h10.5a1.5 1.5 0 0 0 1.5-1.5V9M9 21v-7.5h6V21",
    assistant: "m12 3 1.9 5.6L19.5 10.5l-5.6 1.9L12 18l-1.9-5.6-5.6-1.9 5.6-1.9L12 3ZM19 17l.7 1.3L21 19l-1.3.7L19 21l-.7-1.3L17 19l1.3-.7L19 17Z",
    users: "M16 19.5a4.5 4.5 0 0 0-9 0M11.5 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM18 12a3 3 0 0 0-.5-5.9M19 19.5h2a4 4 0 0 0-3.5-3.97M3 19.5h14",
    payments: "M3 7.5A2.5 2.5 0 0 1 5.5 5h13A2.5 2.5 0 0 1 21 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 16.5v-9ZM3 10h18M7 15h3",
    communication: "M20.5 11.5a8.5 8.5 0 0 1-8.5 8.5 9 9 0 0 1-3.7-.8L4 20l.8-4.3a8.5 8.5 0 1 1 15.7-4.2ZM8 11.5h8m-8 3h5",
    email: "M3 6.75A1.75 1.75 0 0 1 4.75 5h14.5A1.75 1.75 0 0 1 21 6.75v10.5A1.75 1.75 0 0 1 19.25 19H4.75A1.75 1.75 0 0 1 3 17.25V6.75ZM3.5 6.5 12 13l8.5-6.5",
    sms: "M8 2.75h8a1.75 1.75 0 0 1 1.75 1.75v15A1.75 1.75 0 0 1 16 21.25H8a1.75 1.75 0 0 1-1.75-1.75v-15A1.75 1.75 0 0 1 8 2.75ZM10.5 18h3",
    forms: "M9 4.5H7.5A1.5 1.5 0 0 0 6 6v13.5A1.5 1.5 0 0 0 7.5 21h9a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H15M10.5 3h3a1.5 1.5 0 0 1 0 3h-3a1.5 1.5 0 0 1 0-3ZM9 11h6m-6 4h4",
    website_pages: "M3 6.5A2.5 2.5 0 0 1 5.5 4h13A2.5 2.5 0 0 1 21 6.5v11a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5v-11ZM3 9h18M6.5 6.5h.01M9 6.5h.01",
    entities: "m12 2.75 9 5-9 5-9-5 9-5ZM3 12l9 5 9-5M3 16.25l9 5 9-5",
    pages: "M8 3h7l5 5v11a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2ZM15 3v5h5M9.5 12h7m-7 4h7",
    modules: "M3 3h8v8H3V3Zm10 0h8v8h-8V3ZM3 13h8v8H3v-8Zm10 0h8v8h-8v-8Z",
    settings: "M12 15.25a3.25 3.25 0 1 0 0-6.5 3.25 3.25 0 0 0 0 6.5ZM10 3.5h4l.55 2.2 1.2.7 2.18-.62 2 3.44-1.63 1.62v1.32l1.63 1.62-2 3.44-2.18-.62-1.2.7L14 20.5h-4l-.55-2.2-1.2-.7-2.18.62-2-3.44 1.63-1.62v-1.32L4.07 9.22l2-3.44 2.18.62 1.2-.7L10 3.5Z",
    maintenance: "M12 3v4m0 10v4M3 12h4m10 0h4M5.64 5.64l2.83 2.83m7.06 7.06 2.83 2.83m0-12.72-2.83 2.83m-7.06 7.06-2.83 2.83M15.5 12a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0Z"
  }.freeze

  def initialize(key:)
    @key = key
  end

  def call
    tag.svg(tag.path(d: PATHS.fetch(@key)), class: "size-4 shrink-0", viewBox: "0 0 24 24",
            fill: "none", stroke: "currentColor", "stroke-width": "1.7",
            "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true")
  end
end
