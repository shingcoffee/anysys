# frozen_string_literal: true

class PageContentGenerator
  # Renders the HTML for individual composite-page modules.
  #
  # A composite page is assembled from heterogeneous module tiles (list tables,
  # embedded forms, etc.) arranged on a 12-column grid.  This collaborator owns
  # the per-module HTML fragments; the main generator owns the outer grid wrapper
  # and delegates each module here.
  #
  # Usage:
  #   renderer = CompositeRenderer.new
  #   html     = renderer.render_module(mod)
  #
  class CompositeRenderer
    # @param mod [Hash] pre-rendered module descriptor produced by CompositePageRenderer
    # @return [String] HTML fragment for one composite tile
    def render_module(mod)
      width_class      = CompositePageRenderer::WIDTH_CLASSES[mod[:width]] || "col-span-12"
      hidden           = mod[:visibility].is_a?(Hash) && mod[:visibility]["on_event"].present?
      listen_events    = Array(mod.dig(:events, "listen")).join(",")
      visibility_class = hidden ? " hidden" : ""

      lines = []
      lines << "<div data-module-id=\"#{ERB::Util.html_escape(mod[:id].to_s)}\" data-listen-events=\"#{ERB::Util.html_escape(listen_events)}\" " \
               "class=\"#{width_class} bg-white rounded-lg shadow border border-gray-200 " \
               "overflow-hidden#{visibility_class}\">"

      if mod[:title].present?
        lines << "  <div class=\"px-4 py-3 border-b border-gray-200 bg-gray-50\">"
        lines << "    <h3 class=\"text-sm font-semibold text-gray-700\">#{ERB::Util.html_escape(mod[:title])}</h3>"
        lines << "  </div>"
      end

      lines << "  <div class=\"module-content\">"
      lines << (mod[:module_type] == "list" ? render_list_module_html(mod) : "")
      lines << "  </div>"
      lines << "</div>"
      lines.join("\n")
    end

    private

    def render_list_module_html(mod)
      if mod[:records].empty?
        return "    <div class=\"px-6 py-12 text-center text-gray-500\"><p class=\"text-sm\">#{ERB::Util.html_escape(I18n.t("public_views.composite.no_records"))}</p></div>"
      end

      lines = []
      lines << "    <div class=\"overflow-x-auto\" data-controller=\"list-module\" " \
               "data-list-module-module-id-value=\"#{ERB::Util.html_escape(mod[:id].to_s)}\">"
      lines << "      <table class=\"min-w-full divide-y divide-gray-200\">"
      lines << "        <thead class=\"bg-gray-50\"><tr>"
      (mod[:columns] || []).each do |col|
        lines << "          <th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider\">" \
                 "#{ERB::Util.html_escape(col[:name])}</th>"
      end
      if list_has_row_action?(mod)
        lines << "          <th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider\">" \
                 "<span class=\"sr-only\">#{ERB::Util.html_escape(I18n.t("public_views.composite.row_action_default"))}</span></th>"
      end
      lines << "        </tr></thead>"
      lines << "        <tbody class=\"bg-white divide-y divide-gray-200\">"
      mod[:records].each do |record|
        lines << "          <tr class=\"hover:bg-gray-50 cursor-pointer\" " \
                 "data-action=\"click->list-module#selectRow\" data-record-id=\"#{ERB::Util.html_escape(record.id.to_s)}\">"
        (mod[:columns] || []).each do |col|
          value = record.data_json.is_a?(Hash) ? record.data_json[col[:slug].to_s] : ""
          lines << "            <td class=\"px-4 py-3 text-sm text-gray-900\">#{ERB::Util.html_escape(value.to_s)}</td>"
        end
        if list_has_row_action?(mod)
          lines << row_action_cell_html(record, mod)
        end
        lines << "          </tr>"
      end
      lines << "        </tbody>"
      lines << "      </table>"
      lines << "      <div class=\"px-4 py-3 bg-gray-50 border-t text-sm text-gray-500\">" \
               "#{ERB::Util.html_escape(I18n.t("public_views.composite.showing_records", count: mod[:pagination][:total_count]))}</div>"
      lines << "    </div>"
      lines.join("\n")
    end

    def list_has_row_action?(mod)
      Array(mod[:records]).any? { |record| row_action_path_for(record, mod).present? }
    end

    def row_action_path_for(record, mod)
      paths = mod[:row_action_paths]
      paths.is_a?(Hash) ? paths[record.id].to_s : ""
    end

    def row_action_label_for(mod)
      config = mod[:config] || {}
      action = config["row_action"] || config[:row_action]
      label = action.is_a?(Hash) ? (action["label"] || action[:label]).to_s : ""
      label.presence || I18n.t("public_views.composite.row_action_default")
    end

    def row_action_cell_html(record, mod)
      path = row_action_path_for(record, mod)
      cell = "            <td class=\"px-4 py-3 text-sm whitespace-nowrap\">"
      if path.present?
        cell += "<a class=\"text-sm font-medium text-indigo-600 hover:underline\" " \
                "href=\"#{ERB::Util.html_escape(path)}\" " \
                "data-action=\"click->list-module#rowAction\" " \
                "data-record-id=\"#{ERB::Util.html_escape(record.id.to_s)}\" " \
                "data-row-action=\"open\">#{ERB::Util.html_escape(row_action_label_for(mod))}</a>"
      end
      cell + "</td>"
    end
  end
end
