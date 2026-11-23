# frozen_string_literal: true

module EntityDomains
  module Activities
    # Creates or updates a domain's name, description and color. Entities
    # join a domain when they are created into it or moved to it.
    class Save
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)
      ID = /\A[1-9][0-9]*\z/

      class Workflow < Trailblazer::Activity::Railway
        step :scope_customer
        step :validate
        step :persist

        def scope_customer(_ctx, domain:, customer_id:, **)
          domain.errors.clear
          cid = customer_id.to_s.match?(Save::ID) ? customer_id.to_i : nil
          if cid.nil? || (domain.customer_id.present? && domain.customer_id != cid)
            domain.errors.add(:base, I18n.t("maint_core.entity_domains.errors.invalid_customer"))
            return false
          end
          domain.customer_id = cid
          true
        end

        def validate(ctx, domain:, params:, **)
          input = params.to_h.stringify_keys
          attrs = {
            "name" => input.fetch("name", domain.name).to_s.strip,
            "description" => input.fetch("description", domain.description).to_s.strip.presence,
            "color" => input.fetch("color", domain.color).to_s.presence || ::EntityDomain::COLORS.first
          }
          contract = ctx[:contract] = Contracts::EntityDomain.new(domain)
          return true if contract.validate(attrs)

          # Keep the attempted values on the unsaved model for the re-rendered form.
          domain.assign_attributes(attrs)
          contract.errors.each { |error| domain.errors.add(error.attribute, error.message) }
          false
        end

        def persist(_ctx, domain:, contract:, **)
          contract.sync
          domain.save!
          true
        rescue ActiveRecord::RecordNotUnique
          domain.errors.add(:name, I18n.t("maint_core.entity_domains.errors.name_taken"))
          false
        end
      end

      def self.call(domain:, params:, customer_id:)
        signal, = Workflow.call([{ domain: domain, params: params, customer_id: customer_id }, {}])
        Result.new(success?: signal.to_h[:semantic] == :success, model: domain, errors: domain.errors.messages.to_h)
      end
    end
  end
end
