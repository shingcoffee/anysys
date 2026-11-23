# frozen_string_literal: true

# Pagy powers all offset/limit/total_pages pagination math app-wide.
# It is wrapped by ModuleEntriesResolver (admin tables) and Member::PageFilters
# (member surfaces) — controllers/components never build Pagy objects directly.
require "pagy/extras/overflow"
# Load Pagy's built-in locale files into Rails I18n so member-facing pagination
# strings can use the gem's translations instead of app-specific overrides.
require "pagy/extras/i18n"

# Match the app's historical behavior: requesting a page beyond the last one
# returns an empty page at the requested page number instead of raising.
Pagy::DEFAULT[:overflow] = :empty_page
Pagy::DEFAULT.freeze
