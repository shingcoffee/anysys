# frozen_string_literal: true

class RoleBadgeComponent < ApplicationComponent
  ROLE_STYLES = {
    owner: "bg-emerald-100 text-emerald-800",
    admin: "bg-indigo-100 text-indigo-800",
    member: "bg-slate-100 text-slate-800"
  }.freeze

  BASE_CLASSES = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize"

  attr_reader :role

  def initialize(role:)
    @role = role.to_sym
  end

  def role_classes
    "#{BASE_CLASSES} #{ROLE_STYLES.fetch(role, ROLE_STYLES[:member])}"
  end

  def role_label
    t("chrome.customer_form.roles.#{role}")
  end
end
