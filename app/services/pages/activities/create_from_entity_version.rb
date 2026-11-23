# frozen_string_literal: true

module Pages
  module Activities
    # Builds a customer-owned (or shared, on the platform path) page from one
    # entity-version snapshot: the primary entity's fields from that version
    # (associated entities are left out).
    class CreateFromEntityVersion
      Result = Struct.new(:ok, :page, :error_code, :message, keyword_init: true) do
        def success? = ok
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(entity:, version:, customer:, shared: false)
        @entity = entity
        @version = version
        @customer = customer
        @shared = shared
      end

      def call
        if generated_page_for_version
          return failure(:page_exists, I18n.t("maint_core.errors.versions.page_exists"))
        end

        unless @shared
          guard = Billing::Quota::Guard.check(customer: @customer, item_key: "page")
          return failure(:quota, guard.message) unless guard.allowed?
        end

        page = build_page

        Pages::ConfigurationComposer.call(
          page: page,
          template_key: "default",
          theme_preset_key: nil,
          entity: Entities::VersionHydrator.hydrate(@entity, @version)
        )

        if page.save
          Result.new(ok: true, page: page)
        else
          failure(:invalid, page.errors.full_messages.to_sentence)
        end
      rescue ActiveRecord::RecordNotUnique
        failure(:page_exists, I18n.t("maint_core.errors.versions.page_exists"))
      end

      private

      def generated_page_for_version
        scope = Page.where(entity_version_id: @version.id)
        (@shared ? scope.shared : scope.where(customer_id: @customer.id)).first
      end

      def build_page
        page = recyclable_page || Page.new_with_defaults(name: page_name)
        if page.new_record?
          if @shared
            page.skip_tenant_customer_assignment!
            page.customer_id = nil
          else
            page.customer = @customer
          end
        elsif page.deleted?
          page.restore
        end
        page.name = page_name
        page.entity_id = @entity.id
        page.entity_version_id = @version.id
        page
      end

      def page_name
        base = @entity.display_label
        return base unless page_name_taken?(base)

        "#{base} v#{@version.version_number}"
      end

      def page_name_taken?(name)
        scope = Page.with_deleted.where(name: name)
        scope = @shared ? scope.shared : scope.where(customer_id: @customer.id)
        existing = recyclable_page
        scope = scope.where.not(id: existing.id) if existing
        scope.exists?
      end

      def recyclable_page
        return @recyclable_page if defined?(@recyclable_page)

        scope = Page.with_deleted.where(entity_version_id: @version.id)
        scope = @shared ? scope.shared : scope.where(customer_id: @customer.id)
        @recyclable_page = scope.find_by(status: :inactive)
      end

      def failure(code, message)
        Result.new(ok: false, error_code: code, message: message)
      end
    end
  end
end
