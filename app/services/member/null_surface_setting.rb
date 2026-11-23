# frozen_string_literal: true

module Member
  # Stand-in when no SurfaceSetting row exists yet for (customer, surface).
  # Exposes the same overlay surface as Member::SurfaceSetting so the
  # EffectiveSurface wrapper can polymorphically delegate to either object.
  class NullSurfaceSetting
    def enabled_or(default)                 ; default ; end
    def label_or(default)                   ; default ; end
    def icon_or(default)                    ; default ; end
    def subtitle_or(default)                ; default ; end
    def empty_headline_or(default)          ; default ; end
    def empty_body_or(default)              ; default ; end
    def per_page_or(default)                ; default ; end
    def position_or(default)                ; default ; end
    def visible_column_keys                 ; nil   ; end
    def visible_detail_row_keys             ; nil   ; end
    def visible_section_keys                ; nil   ; end
    def row_action_or(_default_label)       ; nil   ; end
  end
end
