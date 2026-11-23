# frozen_string_literal: true

module Pages
  # Rebinds the flowchart that processes a page's submissions. The flowchart
  # must be one the page may bind (PageProcessing#bindable_flowcharts); a
  # launched page also keeps live processing that compiles against its
  # entity, since every submit runs it.
  class ProcessingContract < Reform::Form
    property :flowchart_id

    validate :flowchart_bindable
    validate :launched_page_keeps_working_processing

    def deserialize!(params)
      id = (params["flowchart_id"] || params[:flowchart_id]).to_s.strip.presence
      model.flowchart = id && model.bindable_flowcharts.find_by(id: id)
      { "flowchart_id" => model.flowchart_id }
    end

    private

    def flowchart_bindable
      return if model.flowchart

      errors.add(:flowchart_id, I18n.t("maint_core.errors.validations.page_flowchart_unavailable"))
    end

    def launched_page_keeps_working_processing
      return unless model.flowchart && model.launched?
      return errors.add(:base, I18n.t("maint_core.errors.page_launch.submission_process_offline")) unless model.flowchart.launched?

      Flowcharts::Compatibility.problems(model.flowchart, model.entity).each { |problem| errors.add(:base, problem) }
    end
  end
end
