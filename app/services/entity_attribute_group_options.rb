# frozen_string_literal: true

# Catalog of allowed icon keys + color tokens for entity attribute groups.
# Shared by server-side rendering (helper) and client-side rendering (template_builder
# reads class lists from a `<template>` block, not hardcoded).
module EntityAttributeGroupOptions
  ICONS = {
    "folder"    => :folder,
    "user"      => :user,
    "briefcase" => :briefcase,
    "map-pin"   => :map_pin,
    "mail"      => :mail,
    "phone"     => :phone,
    "calendar"  => :calendar,
    "tag"       => :tag,
    "settings"  => :settings,
    "bell"      => :bell,
    "link"      => :link,
    "file"      => :file
  }.freeze

  COLORS = %w[slate indigo sky teal emerald amber rose violet].freeze

  DEFAULT_ICON  = "folder"
  DEFAULT_COLOR = "slate"
end
