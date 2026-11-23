# frozen_string_literal: true

module FlowchartRuntime
  # Runtime authentication facade. Controllers create the session context from
  # their real request; serialized flowchart input cannot impersonate this type.
  # Warden owns session deserialization (including authenticatable_salt), account
  # activation and timeout hooks. Never reconstruct a principal from a user ID.
  # Pass from_request(request) as ctx[:authentication]; it is request-local and
  # must not be serialized for later executions. Password verification is a
  # credential check, not session establishment or completion of the MFA flow.
  class Authentication
    attr_reader :user

    def initialize(user)
      @user = user
      freeze
    end
    private_class_method :new

    # Keep request/session data and user attributes out of trace inspection.
    def inspect = "#<#{self.class.name}>"

    class << self
      def from_request(request)
        user = nil
        if request.is_a?(ActionDispatch::Request) && (warden = request.env["warden"]).is_a?(Warden::Proxy)
          # Devise hooks throw :warden for revoked/expired sessions. Preserve
          # Warden's logout side effects, but expose nil to the Railway caller.
          catch(:warden) { user = warden.user(:user) }
        end
        new(user)
      end

      def session(context:, customer_id:)
        return unless context.is_a?(self)

        user = context.user
        user if eligible?(user, customer_id) && user.active_for_authentication?
      end

      def password(user:, password:, customer_id:)
        return unless eligible?(user, customer_id)

        if (journal = ::Authentication::PasswordEffects::Scope.journal)
          journal.verify(user: user, password: password, customer_id: customer_id)
        else
          ::Authentication::PasswordVerification.authenticate(user: user, password: password)
        end
      end

      # Returns the extracted token when it matches +expected+ in constant time.
      def token(raw:, expected:, type: "bearer")
        extracted = extract_http_token(raw, type)
        extracted if Crypto.secure_compare(extracted, expected)
      end

      def api_key(raw:, expected:)
        Crypto.secure_compare(raw, expected) || nil
      end

      private

      def extract_http_token(raw, type)
        value = raw.to_s
        case type.to_s
        when "basic" then value.sub(/\ABasic\s+/i, "")
        when "custom" then value
        else value.sub(/\ABearer\s+/i, "")
        end
      end

      def eligible?(user, customer_id)
        user.is_a?(::Authentication::User) && user.persisted? &&
          customer_id.present? && user.customer_id.to_s == customer_id.to_s
      end
    end
  end
end
