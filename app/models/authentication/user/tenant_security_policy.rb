# frozen_string_literal: true

module Authentication
  class User < ApplicationRecord
    # Devise reads timeout_in on the instance, but Lockable 5.0.4's protected
    # threshold hooks read class.maximum_attempts. Override only those hooks;
    # Devise continues to own counting, locking, expiry and unlock behavior.
    module TenantSecurityPolicy
      extend ActiveSupport::Concern

      def timeout_in
        Authentication::Settings.for(customer_id).timeout_in(default: self.class.timeout_in)
      end

      def maximum_attempts
        Authentication::Settings.for(customer_id).maximum_attempts(default: self.class.maximum_attempts)
      end

      protected

      def attempts_exceeded?
        failed_attempts >= maximum_attempts
      end

      def last_attempt?
        failed_attempts == maximum_attempts - 1
      end
    end
  end
end
