# frozen_string_literal: true

# Single source of truth for "which audience is this entity attribute's
# validation running for?".
#
# Used across:
# - EntityAttributeAudience::ContractScope (runtime gate on EntityEntryContract)
# - ContractGenerator (generated contract source)
# - Pages::Submit (viewer -> audience for the flowchart context)
#
# An attribute's validators run for an audience only when the attribute is
# visible to that audience, editable by it, AND flagged to apply validators
# there (`visibility` ∩ `editable` ∩ `validator_apply`). The maps are optional and default to
# "true for every audience", matching the entity form's client-side coercion in
# `app/javascript/controllers/entity_form/schema_manager.js`.
#
module EntityAttributeAudience
  ADMIN  = "admin"
  MEMBER = "member"
  PUBLIC = "public"

  AUDIENCES = [ADMIN, MEMBER, PUBLIC].freeze

  # Reserved-role precedence mirrors Authentication::User#primary_role_key:
  # owner and admin both act on the admin surface.
  ROLE_AUDIENCES = { "owner" => ADMIN, "admin" => ADMIN, "member" => MEMBER }.freeze

  module_function

  # Audiences whose submissions must satisfy this attribute's validators.
  #
  # @param attr [Hash] one property_schema entry
  # @return [Array<String>] ordered subset of AUDIENCES (possibly empty)
  def applying_audiences(attr)
    AUDIENCES.select do |audience|
      enabled?(attr, "visibility", audience) && enabled?(attr, "editable", audience) && enabled?(attr, "validator_apply", audience)
    end
  end

  # True when the given list covers every audience, i.e. no guard is needed.
  def every_audience?(audiences)
    audiences.size == AUDIENCES.size
  end

  # A role grants field visibility only within the visited tenant. Foreign
  # signed-in visitors remain public; the fixed platform owner may administer
  # any tenant. Keep the request's actor intact for authentication and auditing.
  #
  # @param user [Authentication::User, nil]
  # @return [String] one of AUDIENCES
  def for_user(user, customer_id: Current.customer_id)
    return PUBLIC unless tenant_viewer?(user, customer_id: customer_id)

    ROLE_AUDIENCES.fetch(user.primary_role_key, PUBLIC)
  end

  def tenant_viewer?(user, customer_id: Current.customer_id)
    return false if user.nil? || customer_id.blank?

    user.customer_id.to_s == customer_id.to_s || user.platform_owner?
  end

  # True when the attribute is visible to the given audience. Submitted values
  # for an attribute hidden from the acting audience must never be accepted.
  #
  # @param attr [Hash] one property_schema entry
  # @param audience [String, Symbol, nil] blank means "unscoped run", i.e. visible
  # @return [Boolean]
  def visible_to?(attr, audience)
    audience = audience&.to_s
    return true if audience.blank?

    enabled?(attr, "visibility", audience)
  end

  # True when the audience sees the attribute and may change it (`editable`,
  # default true everywhere). A field it sees but may not change is shown
  # read-only, and anything it posts for it is ignored.
  #
  # @param attr [Hash] one property_schema entry
  # @param audience [String, Symbol, nil] blank means "unscoped run", i.e. editable
  # @return [Boolean]
  def editable_by?(attr, audience)
    audience = audience&.to_s
    return true if audience.blank?

    enabled?(attr, "visibility", audience) && enabled?(attr, "editable", audience)
  end

  # Runtime guard handed to ActiveModel `validates ..., if:`.
  #
  # reform-rails runs validations through a SimpleDelegator wrapper, so the proc
  # must dispatch by *method name* (forwarded to the form) rather than through
  # `self.class` (which is the wrapper). `validators_apply_to_audience?` ends in
  # `?`, which an entity attribute slug can never produce — so no property can
  # ever shadow it.
  #
  # @param audiences [Array<String>]
  # @return [Proc]
  def contract_guard(audiences)
    audiences = audiences.dup.freeze
    -> { validators_apply_to_audience?(audiences) }
  end

  # Source-code twin of #contract_guard, emitted by ContractGenerator so the
  # generated contract and the runtime factory can never drift apart.
  #
  # @param audiences [Array<String>]
  # @return [String] a Ruby `if:` option fragment
  def contract_guard_source(audiences)
    "if: -> { validators_apply_to_audience?(#{audiences.inspect}) }"
  end

  # Reads an audience flag map off a schema entry. A missing/blank map means
  # "enabled everywhere"; only an explicit `false` disables an audience.
  def enabled?(attr, key, audience)
    return true unless attr.is_a?(Hash)

    flags = attr[key] || attr[key.to_sym]
    return true if flags.blank? || !flags.is_a?(Hash)

    flags[audience] != false && flags[audience.to_sym] != false
  end
  private_class_method :enabled?

  # Audience slot for contract classes.
  #
  # The audience is immutable CLASS state, not instance state:
  # `EntityEntryContract.build_for` mints a fresh subclass per call, so each
  # request already gets its own class, and keeping it off the instance means
  # neither a Reform property nor a submitted param can overwrite the audience
  # and downgrade its own validation.
  module ContractScope
    extend ActiveSupport::Concern

    included do
      class_attribute :default_validation_audience, instance_accessor: false, default: nil
    end

    class_methods do
      # @return [String, nil] audience this contract class validates for
      def validation_audience
        default_validation_audience
      end

      # True when this class's audience is one the validators apply to.
      # A blank audience means "unscoped run" (activity traces, console, jobs)
      # and applies every declared validator.
      def validators_apply_to_audience?(audiences)
        audience = validation_audience
        audience.blank? || audiences.include?(audience)
      end
    end

    # Instance-side entry point used by the `if:` guards. Runs with `self` bound
    # to the real form even when reform-rails forwards it through its validator
    # delegator, so `self.class` resolves to the built contract class.
    def validators_apply_to_audience?(audiences)
      self.class.validators_apply_to_audience?(audiences)
    end
  end
end
