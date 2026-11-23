# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  class CodeGeneratorsController < ApplicationController
    dashboard_menu_item :maintenance
    before_action :set_generator_info, only: [:show, :edit, :update, :destroy]

    def index
      registry = ::CodeGenerators::GeneratorRegistry.instance
      @step_actions  = registry.step_action_generators
      @element_types = registry.element_type_generators

      @category     = params[:category]
      @kind         = params[:kind]
      @element_type = params[:element_type]

      presenter          = build_presenter
      @sidebar_data      = presenter.sidebar_data
      @search_index      = presenter.search_index
      @filtered_generators = presenter.filtered_generators
    end

    def show
      @source_code    = File.read(@file_path)
      @generator_class = @registry_entry

      unless turbo_frame_request?
        registry       = ::CodeGenerators::GeneratorRegistry.instance
        @step_actions  = registry.step_action_generators
        @element_types = registry.element_type_generators

        presenter     = build_presenter
        @sidebar_data = presenter.sidebar_data
        @search_index = presenter.search_index
      end
    end

    def new
      @kind     = params[:kind]     || "step_action"
      @category = params[:category] || "uncategorized"
      @form_data = ::CodeGenerators::FormDataExtractor.new(params).default_form_data
    end

    def create
      source    = assemble_source
      file_path = build_file_path(params[:kind], params[:file_name], params[:category])
      return unless file_path

      if File.exist?(file_path)
        @errors   = [t("maint_platform.flash.code_generators.file_exists", file: File.basename(file_path))]
        @kind     = params[:kind]
        @category = params[:category]
        @form_data = ::CodeGenerators::FormDataExtractor.new(params).form_data_from_params
        render :new, status: :unprocessable_entity
        return
      end

      save_generator(file_path, source) do
        redirect_to admin_maintenance_platform_code_generator_path(current_customer_id, slug: relative_path(file_path)), notice: t("maint_platform.flash.code_generators.created")
      end
    end

    def edit
      @form_data = { methods_body: ::CodeGenerators::SourceDocument.new(File.read(@file_path)).body }
    end

    def update
      old_body = capture_body(@registry_entry)
      source   = assemble_source

      save_generator(@file_path, source) do
        new_class = reload_and_find_generator
        new_body  = capture_body(new_class)

        if old_body != new_body && new_class
          current_version = new_class._metadata[:version] || "1.0.0"
          new_version     = ::CodeGenerators::MetadataDSL.bump_patch(current_version)
          bump_version_in_file(@file_path, current_version, new_version)
          Rails.autoloaders.main.reload
          ::CodeGenerators::GeneratorRegistry.instance.reload!
          redirect_to admin_maintenance_platform_code_generator_path(current_customer_id, slug: relative_path(@file_path)),
                      notice: t("maint_platform.flash.code_generators.updated_versioned", version: new_version)
        else
          redirect_to admin_maintenance_platform_code_generator_path(current_customer_id, slug: relative_path(@file_path)),
                      notice: t("maint_platform.flash.code_generators.updated")
        end
      end
    end

    def destroy
      File.delete(@file_path) if File.exist?(@file_path)
      Rails.autoloaders.main.reload
      ::CodeGenerators::GeneratorRegistry.instance.reload!

      redirect_to "/#{current_customer_id}/admin/maintenance/platform/code_generators", notice: t("maint_platform.flash.code_generators.deleted")
    end

    private

    def set_generator_info
      relative = params[:slug].to_s
      if relative.include?("..")
        head :bad_request
        return
      end

      @file_path      = Rails.root.join("app/services/code_generators", "#{relative}.rb")
      @registry_entry = ::CodeGenerators::PathIdentity.find(relative)
      head :not_found unless @registry_entry && File.file?(@file_path)
    end

    # -----------------------------------------------------------------
    # Helpers kept in the controller because the request spec stubs them
    # via allow_any_instance_of(CodeGeneratorsController).
    # -----------------------------------------------------------------

    def capture_body(generator_class)
      return nil unless generator_class

      sample  = generator_class.sample_input
      element = { "config" => sample, "properties" => sample, "label" => "version_check" }
      generator_class.new(element, {}).generate_body
    rescue StandardError
      nil
    end

    def bump_version_in_file(file_path, old_version, new_version)
      source  = File.read(file_path)
      updated = source.sub(/version\s+["']#{Regexp.escape(old_version)}["']/, "version \"#{new_version}\"")
      File.write(file_path, updated)
    end

    # -----------------------------------------------------------------
    # Internal helpers
    # -----------------------------------------------------------------

    def build_presenter
      ::CodeGenerators::IndexPresenter.new(
        customer_id:   current_customer_id,
        step_actions:  @step_actions,
        element_types: @element_types,
        category:      @category,
        kind:          @kind,
        element_type:  @element_type
      )
    end

    def generator_params
      params.permit(:kind, :file_name, :category, :description, :version,
                    :registered_names, :methods_body)
    end

    def assemble_source
      ::CodeGenerators::SourceAssembler.new(generator_params, source: @file_path && File.read(@file_path)).assemble
    end

    def build_file_path(kind, file_name, category = nil)
      name = file_name.to_s.underscore
      cat = (category.presence || "uncategorized").underscore
      if unsafe_generator_path_component?(name) || unsafe_generator_path_component?(cat)
        head :bad_request
        return nil
      end
      name = "#{name}_generator" unless name.end_with?("_generator")

      file_path = if kind == "element_type"
        type_name = name.sub(/_generator$/, "")
        Rails.root.join("app/services/code_generators/element_types", type_name, "#{name}.rb")
      else
        Rails.root.join("app/services/code_generators/element_types/process", cat, "#{name}.rb")
      end

      root = Rails.root.join("app/services/code_generators").expand_path.to_s
      expanded = file_path.expand_path.to_s
      unless expanded.start_with?("#{root}#{File::SEPARATOR}")
        head :bad_request
        return nil
      end

      file_path
    end

    def unsafe_generator_path_component?(value)
      value.blank? || value.include?("..") || value.start_with?("/") || value.include?("/")
    end

    def relative_path(file_path)
      Pathname.new(file_path)
              .relative_path_from(Rails.root.join("app/services/code_generators"))
              .to_s.delete_suffix(".rb")
    end

    def save_generator(file_path, source)
      validation_errors = ::CodeGenerators::GeneratorValidator.validate_source(source)
      if validation_errors.any?
        @errors   = validation_errors
        @kind     = params[:kind]
        @category = params[:category]
        @form_data = ::CodeGenerators::FormDataExtractor.new(params).form_data_from_params
        action     = File.exist?(file_path) ? :edit : :new
        render action, status: :unprocessable_entity
        return
      end

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, source)
      Rails.autoloaders.main.reload
      ::CodeGenerators::GeneratorRegistry.instance.reload!

      yield
    end

    def reload_and_find_generator
      ::CodeGenerators::PathIdentity.find(params[:slug])
    end
  end
end
end
end
