# frozen_string_literal: true

module EntityAttributeGroupingHelper
  COLOR_CLASS_MAP = {
    "slate"   => { bar: "bg-slate-500",   text: "text-slate-700",   icon: "text-slate-500",   soft: "bg-slate-100 text-slate-600 ring-slate-500/15"     },
    "indigo"  => { bar: "bg-indigo-500",  text: "text-indigo-700",  icon: "text-indigo-500",  soft: "bg-indigo-50 text-indigo-600 ring-indigo-500/15"   },
    "sky"     => { bar: "bg-sky-500",     text: "text-sky-700",     icon: "text-sky-500",     soft: "bg-sky-50 text-sky-600 ring-sky-500/15"            },
    "teal"    => { bar: "bg-teal-500",    text: "text-teal-700",    icon: "text-teal-500",    soft: "bg-teal-50 text-teal-600 ring-teal-500/15"         },
    "emerald" => { bar: "bg-emerald-500", text: "text-emerald-700", icon: "text-emerald-500", soft: "bg-emerald-50 text-emerald-600 ring-emerald-500/15" },
    "amber"   => { bar: "bg-amber-500",   text: "text-amber-700",   icon: "text-amber-500",   soft: "bg-amber-50 text-amber-600 ring-amber-500/15"      },
    "rose"    => { bar: "bg-rose-500",    text: "text-rose-700",    icon: "text-rose-500",    soft: "bg-rose-50 text-rose-600 ring-rose-500/15"         },
    "violet"  => { bar: "bg-violet-500",  text: "text-violet-700",  icon: "text-violet-500",  soft: "bg-violet-50 text-violet-600 ring-violet-500/15"   }
  }.freeze

  ICON_PATHS = {
    "folder"    => "M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V7z",
    "user"      => "M16 11a4 4 0 11-8 0 4 4 0 018 0zM4 21a8 8 0 0116 0",
    "briefcase" => "M6 7V6a2 2 0 012-2h8a2 2 0 012 2v1m2 0H4v12a2 2 0 002 2h12a2 2 0 002-2V7z",
    "map-pin"   => "M12 21s-7-7.05-7-12a7 7 0 1114 0c0 4.95-7 12-7 12zm0-9a3 3 0 100-6 3 3 0 000 6z",
    "mail"      => "M3 8l9 6 9-6M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
    "phone"     => "M3 5a2 2 0 012-2h2l2 5-3 2a11 11 0 006 6l2-3 5 2v2a2 2 0 01-2 2A17 17 0 013 5z",
    "calendar"  => "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
    "tag"       => "M7 7h.01M21 12l-9 9-9-9V3h9l9 9z",
    "settings"  => "M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.34 1.87l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.7 1.7 0 00-1.87-.34 1.7 1.7 0 00-1 1.55V21a2 2 0 11-4 0v-.09a1.7 1.7 0 00-1-1.55 1.7 1.7 0 00-1.87.34l-.06.06A2 2 0 113.27 16.93l.06-.06A1.7 1.7 0 003.67 15a1.7 1.7 0 00-1.55-1H2a2 2 0 110-4h.09A1.7 1.7 0 003.67 9a1.7 1.7 0 00-.34-1.87l-.06-.06A2 2 0 116.1 4.24l.06.06a1.7 1.7 0 001.87.34h.07a1.7 1.7 0 001-1.55V3a2 2 0 014 0v.09a1.7 1.7 0 001 1.55 1.7 1.7 0 001.87-.34l.06-.06a2 2 0 112.83 2.83l-.06.06a1.7 1.7 0 00-.34 1.87v.07a1.7 1.7 0 001.55 1H22a2 2 0 010 4h-.09a1.7 1.7 0 00-1.55 1z",
    "bell"      => "M15 17h5l-1.4-1.4A2 2 0 0118 14.2V11a6 6 0 10-12 0v3.2a2 2 0 01-.6 1.4L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9",
    "link"      => "M10 14a5 5 0 007.07 0l3-3a5 5 0 00-7.07-7.07l-1 1m-4 12a5 5 0 01-7.07 0 5 5 0 010-7.07l3-3a5 5 0 017.07 0l1 1",
    "file"      => "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z M14 2v6h6"
  }.freeze

  def attribute_group_color_classes(color, variant: :bar)
    token = COLOR_CLASS_MAP.key?(color.to_s) ? color.to_s : EntityAttributeGroupOptions::DEFAULT_COLOR
    COLOR_CLASS_MAP[token][variant] || COLOR_CLASS_MAP[token][:bar]
  end

  def attribute_group_icon(icon_key, css_class:)
    tag.svg(class: css_class, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 2) do
      tag.path(d: attribute_group_icon_path(icon_key), "stroke-linecap": "round", "stroke-linejoin": "round")
    end
  end

  def attribute_group_icon_path(icon_key)
    ICON_PATHS.fetch(icon_key.to_s) { ICON_PATHS[EntityAttributeGroupOptions::DEFAULT_ICON] }
  end

  def iterate_grouped_attributes(entity)
    entity.grouped_property_schema.each { |section| yield section[:group], section[:attributes] }
  end
end
