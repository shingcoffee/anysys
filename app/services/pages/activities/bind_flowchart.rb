# frozen_string_literal: true

module Pages
  module Activities
    # Rebinds the flowchart that processes a customer-owned page's
    # submissions, through the same contract as the page's Processing card.
    # +errors+ are the contract's reasons, which name the flowchart and its
    # steps (platform owner only); +reasons+ say the same to any admin.
    class BindFlowchart
      Result = Struct.new(:ok, :page, :errors, :reasons, keyword_init: true)

      def self.call(...) = new(...).call

      def initialize(page:, flowchart_id:)
        raise ArgumentError, "a shared page is rebound on the platform prefix only" if page.customer_id.nil?

        @page = page
        @flowchart_id = flowchart_id
      end

      def call
        contract = Pages::ProcessingContract.new(@page)
        return Result.new(ok: true, page: @page, errors: [], reasons: []) if contract.validate("flowchart_id" => @flowchart_id.to_s) && contract.save

        Result.new(ok: false, page: @page, errors: contract.errors.full_messages, reasons: reasons)
      end

      private

      def reasons
        flowchart = @page.bindable_flowcharts.find_by(id: @flowchart_id)
        return [I18n.t("maint_core.errors.validations.page_processing_unavailable")] unless flowchart
        return [I18n.t("maint_core.errors.page_launch.submission_process_offline")] unless flowchart.launched?

        Flowcharts::Compatibility.errors(flowchart, @page.entity)
      end
    end
  end
end
