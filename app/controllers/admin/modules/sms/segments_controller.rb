# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class SegmentsController < BaseController
        before_action :load_segment, only: %i[show edit update destroy]

        def index
          paginate(tenant_scope(::Sms::Audience::Segment).order(updated_at: :desc),
                   columns: [column(:name, sortable: true, searchable: true), column(:description), column(:updated_at, type: :datetime, sortable: true)])
          render_surface(:index, data: index_data)
        end

        def new
          @segment = ::Sms::Audience::Segment.new(customer: current_customer)
          prepare_form
          render_form(:new)
        end

        def edit
          prepare_form
          render_form(:edit)
        end

        def create
          @segment = ::Sms::Audience::Segment.new(customer: current_customer)
          save_segment(:new)
        end

        def update
          save_segment(:edit)
        end

        def show
          result = ::Sms::Audience::Preview.call(customer: current_customer, rules: @segment.segment_rules)
          if result.success?
            @preview = result.value
            render_surface(:show, data: { segment: public_record(@segment), preview: @preview })
          else
            render_failure(result, template: :show)
          end
        end

        def preview
          @segment = request.path_parameters[:id] ? scoped_find(::Sms::Audience::Segment) : ::Sms::Audience::Segment.new(customer: current_customer)
          attributes = form_attributes(:segment, record: @segment)
          @segment.assign_attributes(attributes.except(:lock_version))
          prepare_form
          template = @segment.persisted? ? :edit : :new
          result = ::Sms::Audience::Preview.call(customer: current_customer, rules: @segment.segment_rules)
          if result.success?
            @preview = result.value
            render_form(template)
          else
            render_failure(result, template: template)
          end
        end

        def destroy
          action_attributes
          result = ::Sms::Audience::DeleteSegment.call(customer: current_customer, actor: current_user, segment: @segment)
          if result.success?
            success_response({ id: result.value.id }, location: admin_modules_sms_segments_path(current_customer_id), notice: :deleted)
          else
            prepare_form
            render_failure(result, template: :show)
          end
        end

        private

        def load_segment
          @segment = scoped_find(::Sms::Audience::Segment)
        end

        def prepare_form
          @catalog = ::Sms::Audience::FieldCatalog.new(customer: current_customer)
          @form_values ||= ::Sms::FormValues.for(@segment, kind: :segment)
          @preview ||= nil
          @errors ||= {}
        end

        def render_form(template)
          render_surface(template, data: { segment: public_record(@segment), form_values: @form_values, preview: @preview, errors: @errors, catalog: @catalog.fields })
        end

        def save_segment(template)
          attributes = form_attributes(:segment, record: @segment)
          result = ::Sms::Audience::SaveSegment.call(customer: current_customer, actor: current_user,
                                                    segment: @segment.persisted? ? @segment : nil, attributes: attributes)
          if result.success?
            @segment = result.value
            success_response(public_record(@segment), location: admin_modules_sms_segment_path(current_customer_id, @segment), status: template == :new ? :created : :ok)
          else
            prepare_form
            render_failure(result, template: template)
          end
        end

        def input_error(error)
          return super if action_name == "index"

          @segment ||= request.path_parameters[:id] ? scoped_find(::Sms::Audience::Segment) : ::Sms::Audience::Segment.new(customer: current_customer)
          @errors = error.errors
          @form_values = ::Sms::FormValues.for(@segment, kind: :segment).merge(error.form_values)
          prepare_form
          render_failure(error, template: action_name == "destroy" ? :show : (@segment.persisted? ? :edit : :new))
        end
      end
    end
  end
end
