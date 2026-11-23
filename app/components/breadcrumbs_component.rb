# frozen_string_literal: true

class BreadcrumbsComponent < ApplicationComponent
  def initialize(crumbs:) = @crumbs = crumbs
  attr_reader :crumbs
end
