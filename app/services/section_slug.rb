# frozen_string_literal: true

# SectionSlug
#
# Canonical slug for form-section / bridge-entity param keys. This mapping is
# shared by the generator (PageContentGenerator::FormFields), the param router
# (FormParamsRouter), and the activity step (ActivitySteps::DetectAndRouteParams)
# so generated field names and submitted params always agree.
#
# NOTE: intentionally NOT String#parameterize — parameterize transliterates
# accented characters (café → cafe) whereas this mapping strips them (café →
# caf). Page configurations already persisted were generated with this exact
# mapping, so it must stay byte-stable.
module SectionSlug
  module_function

  def for(name)
    name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
  end
end
