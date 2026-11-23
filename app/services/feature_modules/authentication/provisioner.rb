# frozen_string_literal: true

module FeatureModules
  module Authentication
    # Provisioner
    #
    # Sets up authentication for a customer when the module is enabled.
    # Creates an initial admin user if no users exist for the customer.
    # The platform owner customer gets the pinned owner account; every
    # other customer gets an `admin` (full access within their tenant).
    #
    class Provisioner
      def self.call(customer)
        customer.with_lock(requires_new: true) { provision_user(customer) }
      end

      def self.provision_user(customer)
        return if ::Authentication::User.where(customer_id: customer.id).exists?

        platform_owner_customer = customer.id == ::Authentication::User::PLATFORM_CUSTOMER_ID

        email =
          if platform_owner_customer
            ::Authentication::User::PLATFORM_OWNER_EMAIL
          elsif customer.contact.present? && customer.contact.match?(URI::MailTo::EMAIL_REGEXP)
            customer.contact
          else
            "admin@#{customer.name.parameterize}.local"
          end

        user = ::Authentication::User.create!(
          customer: customer,
          email: unique_provisioned_email(email, customer),
          first_name: customer.name.split.first || "Admin",
          last_name: customer.name.split.last || "User",
          password: SecureRandom.hex(16),
          status: :active,
          confirmed_at: Time.current
        )

        role_key = platform_owner_customer ? "owner" : "admin"
        role = customer.roles.system.find_by!(key: role_key)
        user.users_roles.create!(role: role)

        user
      end
      private_class_method :provision_user

      # Email is globally unique. If the preferred address is already taken
      # (another tenant used the same contact or parameterized name), suffix
      # with the customer id. The platform-owner email is never rewritten.
      def self.unique_provisioned_email(email, customer)
        return email if customer.id == ::Authentication::User::PLATFORM_CUSTOMER_ID

        normalized = email.to_s.downcase.strip
        return email unless ::Authentication::User.exists?([ "LOWER(email) = ?", normalized ])

        local, domain = email.to_s.split("@", 2)
        return email if domain.blank?

        "#{local}+#{customer.id}@#{domain}"
      end
      private_class_method :unique_provisioned_email
    end
  end
end
