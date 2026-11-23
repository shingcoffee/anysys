# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class ContactsController < BaseController
        before_action :load_contact, only: %i[show edit update destroy]

        def index
          paginate(tenant_scope(::Sms::Contact).order(updated_at: :desc),
                   columns: [column(:name, sortable: true, searchable: true), column(:phone_e164, sortable: true, searchable: true),
                             status_column(:consent_status), status_column(:status, namespace: :contact_status),
                             column(:country_code, sortable: true), column(:timezone),
                             column(:source_kind, cell: ->(contact) { t("sms_campaign_http.source_kind.#{contact.source_kind}") }),
                             column(:updated_at, type: :datetime, sortable: true)],
                   accepted: %i[q status consent_status source_kind page per_page sort dir],
                   enums: { status: %w[active archived], consent_status: %w[unknown granted revoked], source_kind: %w[manual entity] },
                   filters: %i[status consent_status source_kind].map { |key| { key: key, column: key } })
          render_surface(:index, data: index_data)
        end

        def new
          @contact = ::Sms::Contact.new(customer: current_customer)
          prepare_form
          render_surface(:new, data: { form_values: @form_values, errors: @errors })
        end

        def edit
          prepare_form
          render_surface(:edit, data: { contact: public_record(@contact), form_values: @form_values, errors: @errors })
        end

        def create
          @contact = ::Sms::Contact.new(customer: current_customer)
          save_contact(:new, :created)
        end

        def update
          save_contact(:edit, :saved)
        end

        def show
          prepare_show
          render_surface(:show, data: { contact: public_record(@contact), eligibility: @eligibility,
                                       consent_events: { records: @consent_events[:records].map { |event| event.attributes.except("customer_id") }, pagination: @consent_events[:pagination] } })
        end

        def destroy
          raw = action_attributes(:lock_version)
          version = ::Sms::RequestAttributes.integer(raw[:lock_version], field: :lock_version)
          result = ::Sms::Contacts::Archive.call(customer: current_customer, actor: current_user, contact: @contact, lock_version: version)
          if result.success?
            success_response(public_record(result.value), location: admin_modules_sms_contact_path(current_customer_id, @contact), notice: :archived)
          else
            prepare_show
            render_failure(result, template: :show)
          end
        end

        private

        def load_contact
          @contact = scoped_find(::Sms::Contact)
        end

        def save_contact(template, notice)
          attributes = form_attributes(:contact, record: @contact)
          result = ::Sms::Contacts::Save.call(customer: current_customer, actor: current_user,
                                             contact: @contact.persisted? ? @contact : nil, attributes: attributes)
          if result.success?
            @contact = result.value
            success_response(public_record(@contact), location: admin_modules_sms_contact_path(current_customer_id, @contact),
                             status: template == :new ? :created : :ok, notice: notice)
          else
            prepare_form
            render_failure(result, template: template)
          end
        end

        def prepare_form
          @form_values ||= ::Sms::FormValues.for(@contact, kind: :contact)
          @errors ||= {}
        end

        def prepare_show
          @errors ||= {}
          @consent_form_values ||= ::Sms::FormValues.consent
          paging = { page: 1, per_page: 25 }
          %i[page per_page].each do |field|
            raw = request.query_parameters[field.to_s]
            paging[field] = ::Sms::RequestAttributes.integer(raw, field: field, minimum: 1) unless raw.nil?
          end
          paging[:per_page] = [paging[:per_page], 100].min
          result = ModuleEntriesResolver.call(scope: tenant_scope(::Sms::ConsentEvent).where(contact_id: @contact.id).order(id: :desc),
                                               columns: [], params: paging, per_page: 25, max_per_page: 100)
          @consent_events = { records: result[:rows], pagination: result[:pagination] }
          @eligibility = ::Sms::Contacts::Eligibility.call(customer: current_customer, contact: @contact)
        end

        def input_error(error)
          return super unless %w[create update destroy].include?(action_name)

          @contact ||= ::Sms::Contact.new(customer: current_customer)
          @errors = error.errors
          @form_values = ::Sms::FormValues.for(@contact, kind: :contact).merge(error.form_values)
          action_name == "destroy" ? prepare_show : prepare_form
          render_failure(error, template: action_name == "destroy" ? :show : (action_name == "create" ? :new : :edit))
        end
      end
    end
  end
end
