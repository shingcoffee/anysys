# frozen_string_literal: true

module Sms
  module Contacts
    class Archive
      def self.call(customer:, actor:, contact:, lock_version:)
        Save.call(customer: customer, actor: actor, contact: contact,
          attributes: { status: "archived", lock_version: lock_version })
      end
    end
  end
end
