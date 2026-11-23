# frozen_string_literal: true

# One sidebar group: either a Settings section heading wrapped as a disclosure,
# or an optional plain label followed by its nodes.
class SidebarGroupComponent < ApplicationComponent
  attr_reader :group, :current_path, :mobile, :filterable, :selected_key

  def initialize(group:, sectioned:, current_path:, mobile:, filterable:, selected_key:)
    @group = group
    @sectioned = sectioned
    @current_path = current_path
    @mobile = mobile
    @filterable = filterable
    @selected_key = selected_key
  end

  def disclosure?
    @sectioned && group[:header]
  end

  def nodes
    disclosure? ? [group[:header].with_children(group[:nodes])] : group[:nodes]
  end

  def plain_label
    group[:header] unless disclosure?
  end
end
