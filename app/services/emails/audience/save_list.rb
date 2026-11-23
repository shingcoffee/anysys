# frozen_string_literal: true

module Emails
  module Audience
    class SaveList
      def self.call(list:, attributes: {})
        list.assign_attributes(attributes)
        list.errors.clear
        if list.dynamic?
          contract = Contracts::SegmentRules.new(Contracts::SegmentRules::Input.new)
          unless contract.validate(rules: list.segment_rules)
            contract.errors[:rules].each { |message| list.errors.add(:segment_rules, message) }
            return false
          end
        end
        list.save
      end
    end
  end
end
