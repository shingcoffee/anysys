# frozen_string_literal: true

module FlowchartRuntime
  # Allow-listed constant resolution for flowchart service / job / channel /
  # mailer steps. Never resolve arbitrary user strings via Object.const_get.
  module Invocable
    class Error < StandardError; end

    NESTED_CONST_RE = /\A[A-Z][a-zA-Z0-9_]*(::[A-Z][a-zA-Z0-9_]*)*\z/
    METHOD_RE       = /\A[a-z_][a-zA-Z0-9_]*[!?=]?\z/
    FORBIDDEN_METHODS = %w[
      delete_all destroy_all update_all delete destroy
      update_column update_columns insert_all upsert_all
      find_by_sql connection
    ].freeze
    FORBIDDEN_OWNERS = [BasicObject, Kernel, Object, Module, Class].freeze

    # Explicit service allowlist (exact class names). Prefer adding here over
    # opening new namespaces. Namespaced services under SERVICE_NAMESPACES are
    # also accepted when they resolve to a Class.
    SERVICE_ALLOWLIST = %w[
      ApplicationService
    ].freeze

    SERVICE_NAMESPACES = %w[
      Sms
      Emails
      Payments
      Captcha
      FeatureModules
      Member
      Billing
    ].freeze

    MAILER_ALLOWLIST = %w[
      ApplicationMailer
      BillingMailer
      Emails::DeliveryMailer
      Member::MfaMailer
    ].freeze

    module_function

    def service!(name)
      resolve_class!(name, kind: :service) do |klass|
        allowlisted_service?(name.to_s.strip) && klass.is_a?(Class)
      end
    end

    def job!(name)
      resolve_class!(name, kind: :job) do |klass|
        klass.is_a?(Class) && (klass <= ApplicationJob)
      end
    end

    # ActionCable is loaded unconditionally (config/application.rb requires
    # "rails/all"), so the constant is always present. A `defined?` guard here
    # would be an optional fallback that silently rejected every channel if the
    # framework were ever dropped, instead of failing loudly at boot.
    def channel!(name)
      resolve_class!(name, kind: :channel) do |klass|
        klass.is_a?(Class) && (klass < ActionCable::Channel::Base)
      end
    end

    def mailer!(name)
      s = name.to_s.strip
      raise Error, "mailer not allowlisted: #{s}" unless MAILER_ALLOWLIST.include?(s)

      resolve_class!(s, kind: :mailer) do |klass|
        klass.is_a?(Class) && (klass <= ApplicationMailer)
      end
    end

    def method_name!(name)
      s = name.to_s.strip
      raise Error, "invalid method name: #{name.inspect}" unless METHOD_RE.match?(s)
      raise Error, I18n.t("code_generator_rejection_errors.forbidden_method", method: s) if FORBIDDEN_METHODS.include?(s)

      s
    end

    # Permit a method only when it is defined by application code under app/
    # and is not inherited from Object / Kernel / BasicObject / Module / Class.
    # A service that defines its own `send` (Emails::Gateway.send) stays allowed.
    def method!(klass, name, style: "class_method")
      s = method_name!(name)
      meth = lookup_method(klass, s, style.to_s)
      assert_application_owned!(meth, s)
      s
    end

    # App convention: `def self.call(...) = new(...).call` returning a Result.
    def call!(klass, **kwargs)
      method!(klass, "call", style: "call")
      klass.call(**kwargs)
    rescue ArgumentError => error
      raise Error, error.message
    end

    def failed?(result)
      return false if result.nil? || result == true || result == false
      return result.ok == false if result.respond_to?(:ok)
      return result.success? == false if result.respond_to?(:success?)
      return false unless result.is_a?(Hash)

      result[:ok] == false || result["ok"] == false ||
        result[:success] == false || result["success"] == false
    end

    def fail_result(ctx, result)
      messages = result_messages(result)
      return Step.fail(ctx, :"invoke_service.rejected") if messages.empty?

      ctx[:errors] ||= []
      ctx[:error_details] ||= []
      messages.each do |text|
        ctx[:errors] << text unless ctx[:errors].include?(text)
        ctx[:error_details] << {
          "code" => "invoke_service.rejected",
          "field" => nil,
          "message" => text,
          "details" => {}
        }
      end
      false
    end

    def result_messages(result)
      if result.respond_to?(:errors)
        errors = result.errors
        return Array(errors.full_messages).map(&:to_s) if errors.respond_to?(:full_messages)
        return Array(errors).map(&:to_s) if errors.is_a?(Array)
      end
      return Array(result[:errors] || result["errors"]).map(&:to_s) if result.is_a?(Hash)

      message = result.respond_to?(:message) ? result.message : nil
      message.present? ? [message.to_s] : []
    end
    module_function :result_messages
    private_class_method :result_messages

    def allowlisted_service?(name)
      return true if SERVICE_ALLOWLIST.include?(name)
      return true if SERVICE_NAMESPACES.any? { |ns| name == ns || name.start_with?("#{ns}::") }

      false
    end

    def valid_const_name?(name)
      NESTED_CONST_RE.match?(name.to_s.strip)
    end

    def resolve_class!(name, kind:)
      s = name.to_s.strip
      raise Error, "invalid #{kind} class name: #{name.inspect}" unless valid_const_name?(s)

      klass = s.safe_constantize
      raise Error, "unknown #{kind}: #{s}" if klass.nil?
      raise Error, I18n.t("code_generator_rejection_errors.active_record_class") if klass.is_a?(Class) && klass < ActiveRecord::Base
      raise Error, "#{kind} not allowlisted: #{s}" unless yield(klass)

      klass
    end
    module_function :resolve_class!

    def lookup_method(klass, name, style)
      unless klass.is_a?(Module)
        raise Error, I18n.t("code_generator_rejection_errors.forbidden_method", method: name)
      end

      case style
      when "instance_method", "new_and_call"
        klass.instance_method(name)
      else
        klass.method(name)
      end
    rescue NameError
      raise Error, I18n.t("code_generator_rejection_errors.forbidden_method", method: name)
    end
    module_function :lookup_method

    def assert_application_owned!(meth, name)
      # Class#new is the allocator; the application-defined constructor is
      # initialize. Permit `new` only when that initialize lives under app/.
      if name.to_s == "new" && meth.owner == Class && meth.is_a?(Method) && meth.receiver.is_a?(Module)
        begin
          meth = meth.receiver.instance_method(:initialize)
        rescue NameError
          raise Error, I18n.t("code_generator_rejection_errors.forbidden_method", method: name)
        end
      end

      owner = meth.owner
      if FORBIDDEN_OWNERS.include?(owner)
        raise Error, I18n.t("code_generator_rejection_errors.forbidden_method", method: name)
      end

      path = meth.source_location&.first
      app_root = Rails.root.join("app").to_s
      unless path&.start_with?(app_root)
        raise Error, I18n.t("code_generator_rejection_errors.forbidden_method", method: name)
      end
    end
    module_function :assert_application_owned!
  end
end
