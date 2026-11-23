# frozen_string_literal: true

# Spec stand-in for assigning Customer#domain without DNS verification.
module CustomDomainRecord
  class Row
    attr_reader :domain, :customer_id

    alias_method :hostname, :domain
    alias_method :id, :domain

    def initialize(domain:, customer_id:)
      @domain = domain
      @customer_id = customer_id
    end

    def reload
      owner_id = @domain.present? ? Customer.domain_owner_id(@domain) : nil
      if owner_id
        @customer_id = owner_id
        @domain = Customer.unscoped.find(owner_id).domain
      end
      self
    end

    def update!(hostname: nil, domain: nil, customer_id: nil)
      new_name = CustomDomainRecord.normalize!(hostname || domain || @domain)
      new_owner_id = customer_id || @customer_id
      source = Customer.unscoped.find(@customer_id)
      target = Customer.unscoped.find(new_owner_id)
      source.update_columns(domain: nil) unless source.id == target.id
      target.update_columns(domain: new_name)
      @domain = new_name
      @customer_id = target.id
      self
    end

    def destroy!
      Customer.unscoped.find(@customer_id).update_columns(domain: nil) if @customer_id
      @domain = nil
      self
    end
  end

  module_function

  def normalize!(value)
    name = PageShortcuts::Hosts.normalize(value.to_s)
    raise ArgumentError, "invalid domain #{value.inspect}" if name.blank?

    name
  end

  def create!(hostname: nil, domain: nil, customer_id: nil, customer: nil)
    owner = customer || Customer.unscoped.find(customer_id)
    name = normalize!(domain || hostname)
    owner.update_columns(domain: name)
    Row.new(domain: name, customer_id: owner.id)
  end

  def exists?(id = nil, **kwargs)
    raw = kwargs.fetch(:id) { id }
    raw = raw[:id] if raw.is_a?(Hash)
    name = PageShortcuts::Hosts.normalize(raw.to_s) || raw.to_s
    Customer.domain_owner_id(name).present?
  end
end
