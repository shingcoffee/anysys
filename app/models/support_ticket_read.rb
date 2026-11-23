# frozen_string_literal: true

# Per-user read cursor on a help ticket. customer_id is the ticket's tenant
# (not the viewer's acting-as customer) so the platform owner has one cursor
# per ticket regardless of which tenant URL they are on.
class SupportTicketRead < ApplicationRecord
  belongs_to :support_ticket, inverse_of: :reads
  belongs_to :user, class_name: "Authentication::User"
  belongs_to :customer

  # Idempotent under concurrent show/reply: a unique-index race must
  # become an update of last_read_at, not a 500.
  def self.record!(support_ticket:, user_id:)
    now = Time.current
    row = find_or_initialize_by(support_ticket_id: support_ticket.id, user_id: user_id)
    row.customer_id = support_ticket.customer_id
    row.last_read_at = now
    row.save!
    row
  rescue ActiveRecord::RecordNotUnique
    row = find_by!(support_ticket_id: support_ticket.id, user_id: user_id)
    row.update!(last_read_at: now, customer_id: support_ticket.customer_id)
    row
  end

  def self.last_read_at_for(user_id:, support_ticket_id:)
    return nil if user_id.blank? || support_ticket_id.blank?

    where(user_id: user_id, support_ticket_id: support_ticket_id).pick(:last_read_at)
  end
end
