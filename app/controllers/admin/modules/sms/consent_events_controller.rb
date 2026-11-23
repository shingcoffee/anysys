# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class ConsentEventsController < ContactsController
        before_action :load_consent_contact, only: :create

        def create
          attributes = form_attributes(:consent_event)
          @consent_form_values = @form_values
          result = ::Sms::Contacts::RecordConsent.call(customer: current_customer, actor: current_user, contact: @contact, attributes: attributes)
          if result.success?
            value = result.value
            success_response({ contact: public_record(value[:contact]), event_id: value[:event].id, replayed: value[:replayed] },
                             location: admin_modules_sms_contact_path(current_customer_id, @contact), status: :created, notice: :consent_recorded)
          else
            prepare_show
            render_failure(result, template: "admin/modules/sms/contacts/show")
          end
        end

        private

        def load_consent_contact
          @contact = scoped_find(::Sms::Contact, :contact_id)
        end

        def input_error(error)
          @contact ||= scoped_find(::Sms::Contact, :contact_id)
          @errors = error.errors
          @consent_form_values = ::Sms::FormValues.consent.merge(error.form_values)
          prepare_show
          render_failure(error, template: "admin/modules/sms/contacts/show")
        end
      end
    end
  end
end
