# frozen_string_literal: true

# Hidden version-history modal rendered once on a resource index page.
# Parameterized at open time (resource id/name) by the `versions`
# Stimulus controller; this component only renders the static shell + targets.
# The customer id and resource type are carried by the page wrapper's
# data-versions-customer-id-value and data-versions-resource-value attributes —
# the component itself needs no parameters.
class VersionsModalComponent < ApplicationComponent
end
