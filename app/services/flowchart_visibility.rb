# frozen_string_literal: true

# Flowcharts are an owner-only engine. Customers never see the editor, nav,
# or the word; bound pages still execute. Ask this object before contributing
# chrome, mentioning flowcharts in the assistant, or linking to the editor.
#
# HTTP enforcement lives in RouteAuthorization (path + controller) and Ability
# (CanCan subjects). This object is the single predicate those layers share so
# a new nested flowchart controller cannot be forgotten in one place.
module FlowchartVisibility
  module_function

  ROUTE_SUBJECT_PREFIX = "route_admin_maintenance_flowchart"

  def allowed?(user)
    user.respond_to?(:platform_owner?) && user.platform_owner?
  end

  def controller?(controller_path)
    controller_path.to_s.match?(%r{(?:\A|/)flowchart})
  end

  def route_subject?(subject)
    subject.to_s.start_with?(ROUTE_SUBJECT_PREFIX)
  end
end
