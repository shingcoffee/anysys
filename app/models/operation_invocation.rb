# frozen_string_literal: true

class OperationInvocation < ApplicationRecord
  include TenantScoped

  STATUSES = %w[
    awaiting_confirmation succeeded invalid conflict forbidden failed superseded declined
  ].freeze
  CHANNELS = Operations::Context::CHANNELS

  belongs_to :user, class_name: "Authentication::User", optional: true
  belongs_to :confirmed_by, class_name: "Authentication::User", optional: true

  validates :customer_id, :operation, :operation_version, :channel, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :channel, inclusion: { in: CHANNELS }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
    scope name, -> { where(status: name) }
  end
end
