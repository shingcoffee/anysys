# frozen_string_literal: true

module Help
  module Activities
    class CreateRequest
      def self.call(customer:, user:, params:)
        request = SupportTicket.new(customer: customer, user: user, status: "open")
        attributes = sanitize(params)
        contract = Help::Contracts::Request.new(request)
        unless contract.validate(attributes)
          return Help::Result.new(success?: false, model: request,
                                  errors: contract.errors.messages.to_h,
                                  messages: contract.errors.full_messages)
        end

        persist!(request, user: user, customer: customer, attributes: attributes)
        message = request.messages.max_by { |row| [ row.created_at, row.id ] }
        Notifications::Stream.broadcast_help!(request: request, message: message) if message
        Help::Result.new(success?: true, model: request, errors: {}, messages: [])
      end

      def self.sanitize(params)
        params.to_h.symbolize_keys.slice(:subject, :body, :images)
      end
      private_class_method :sanitize

      def self.persist!(request, user:, customer:, attributes:)
        now = Time.current
        SupportTicket.transaction do
          request.assign_attributes(subject: attributes[:subject].to_s.strip, last_message_at: now)
          request.save!
          message = request.messages.create!(
            customer_id: customer.id,
            user_id: user.id,
            author_role: "requester",
            body: attributes[:body].to_s.strip
          )
          Help::AttachmentRules.attach_images!(message, attributes[:images])
          SupportTicketRead.record!(support_ticket: request, user_id: user.id)
        end
      end
      private_class_method :persist!
    end
  end
end
