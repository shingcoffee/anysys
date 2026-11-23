# frozen_string_literal: true

module Sms
  class ConsentEvent < ApplicationRecord
    include TenantScoped
    self.table_name = "sms_consent_events"

    ACTIONS = %w[granted revoked].freeze
    SOURCES = %w[admin recipient_unsubscribe provider_opt_out].freeze

    belongs_to :contact, class_name: "Sms::Contact"
    belongs_to :actor_user, class_name: "Authentication::User", optional: true
    validates :customer_id, :phone_e164, :occurred_at, :event_key, presence: true
    validates :action, inclusion: { in: ACTIONS }
    validates :source, inclusion: { in: SOURCES }
    validates_with Sms::TenantReferences, attributes: %i[contact actor_user], actors: %i[actor_user]

    # Covers update_columns, touch and destroy. AR's delete skips readonly?, so
    # it is explicitly fenced too. Bulk SQL is reserved for database maintenance.
    def readonly? = persisted?

    def delete
      raise ActiveRecord::ReadOnlyRecord if persisted?
      super
    end
  end
end
