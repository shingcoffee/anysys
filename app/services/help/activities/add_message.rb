# frozen_string_literal: true

module Help
  module Activities
    class AddMessage
      def self.call(request:, user:, author_role:, params:)
        result = request.with_lock do
          write_message(request: request, user: user, author_role: author_role, params: params)
        end
        if result.success?
          ActiveRecord.after_all_transactions_commit do
            Notifications::Stream.broadcast_help!(request: request, message: result.model)
          end
        end
        result
      end

      def self.write_message(request:, user:, author_role:, params:)
        message = request.messages.build(
          customer_id: request.customer_id,
          user_id: user.id,
          author_role: author_role
        )
        attributes = sanitize(params)

        if request.resolved?
          return Help::Result.new(
            success?: false, model: message, errors: { base: [ I18n.t("help.errors.resolved") ] },
            messages: [ I18n.t("help.errors.resolved") ]
          )
        end

        unless SupportTicketMessage::AUTHOR_ROLES.include?(author_role.to_s)
          return Help::Result.new(
            success?: false, model: message, errors: { base: [ I18n.t("help.errors.invalid_role") ] },
            messages: [ I18n.t("help.errors.invalid_role") ]
          )
        end

        contract = Help::Contracts::Message.new(message)
        unless contract.validate(attributes)
          return Help::Result.new(success?: false, model: message,
                                   errors: contract.errors.messages.to_h,
                                   messages: contract.errors.full_messages)
        end

        persist!(request, message, attributes)
        Help::Result.new(success?: true, model: message, errors: {}, messages: [])
      end
      private_class_method :write_message

      def self.sanitize(params)
        params.to_h.symbolize_keys.slice(:body, :images)
      end
      private_class_method :sanitize

      def self.persist!(request, message, attributes)
        message.body = attributes[:body].to_s.strip
        message.save!
        Help::AttachmentRules.attach_images!(message, attributes[:images])
        request.update!(last_message_at: message.created_at)
        SupportTicketRead.record!(support_ticket: request, user_id: message.user_id)
      end
      private_class_method :persist!
    end
  end
end
