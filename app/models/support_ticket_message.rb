# frozen_string_literal: true

# One message in a SupportTicket thread. Images attach here so each turn
# can carry screenshots independently of the ticket row.
class SupportTicketMessage < ApplicationRecord
  include TenantScoped

  AUTHOR_ROLES = %w[requester owner].freeze

  belongs_to :support_ticket, inverse_of: :messages
  belongs_to :user, class_name: "Authentication::User"
  has_many_attached :images

  def requester? = author_role == "requester"

  def owner_author? = author_role == "owner"
end
