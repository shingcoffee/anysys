# Part 9: Admin CRUD UI

## Task 18: Routes + Controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/admin/code_generators_controller.rb`
- Test: `spec/controllers/admin/code_generators_controller_spec.rb`

- [ ] **Step 1: Add admin routes**

Add the following block in `config/routes.rb` **before** the catch-all route (before `match "*path"`):

```ruby
  # ==========================================================================
  # Admin Routes (system-level, not tenant-scoped)
  # ==========================================================================
  namespace :admin do
    resources :code_generators, only: [:index, :show, :new, :create, :edit, :update, :destroy], param: :path do
      member do
        post :validate
        get :preview
      end
    end
  end
```

- [ ] **Step 2: Create controller**

```ruby
# app/controllers/admin/code_generators_controller.rb
# frozen_string_literal: true

module Admin
  class CodeGeneratorsController < ApplicationController
    skip_before_action :set_current_customer, raise: false
    before_action :require_admin_role!
    before_action :set_generator_info, only: [:show, :edit, :update, :destroy, :validate, :preview]

    def index
      registry = CodeGenerators::GeneratorRegistry.instance
      @step_actions = registry.step_action_generators
      @element_types = registry.element_type_generators
    end

    def show
      @source_code = File.read(@file_path)
      @generator_class = @registry_entry
    end

    def new
      @kind = params[:kind] || "step_action"
      @source_code = template_for(@kind)
    end

    def create
      file_path = build_file_path(params[:kind], params[:file_name])

      if File.exist?(file_path)
        @errors = ["File already exists: #{File.basename(file_path)}"]
        @source_code = params[:source_code]
        @kind = params[:kind]
        render :new, status: :unprocessable_entity
        return
      end

      save_generator(file_path, params[:source_code]) do
        redirect_to admin_code_generator_path(path: relative_path(file_path)), notice: "Generator created"
      end
    end

    def edit
      @source_code = File.read(@file_path)
    end

    def update
      save_generator(@file_path, params[:source_code]) do
        redirect_to admin_code_generator_path(path: relative_path(@file_path)), notice: "Generator updated"
      end
    end

    def destroy
      File.delete(@file_path) if File.exist?(@file_path)
      Rails.autoloaders.main.reload
      CodeGenerators::GeneratorRegistry.instance.reload!

      redirect_to admin_code_generators_path, notice: "Generator deleted"
    end

    def validate
      errors = CodeGenerators::GeneratorValidator.validate_source(params[:source_code])
      render json: { valid: errors.empty?, errors: errors }
    end

    def preview
      if @registry_entry
        generator = @registry_entry.new({}, {})
        render json: { example_output: generator.example_output }
      else
        render json: { example_output: nil }
      end
    end

    private

    def set_generator_info
      relative = params[:path]
      @file_path = Rails.root.join("app/services/code_generators", "#{relative}.rb")
      basename = File.basename(relative).sub(/_generator$/, "")
      @registry_entry = CodeGenerators::GeneratorRegistry.instance.all_generators[basename]
    end

    def build_file_path(kind, file_name)
      dir = kind == "element_type" ? "element_types" : "step_actions"
      name = file_name.to_s.underscore
      name = "#{name}_generator" unless name.end_with?("_generator")
      Rails.root.join("app/services/code_generators", dir, "#{name}.rb")
    end

    def relative_path(file_path)
      Pathname.new(file_path)
        .relative_path_from(Rails.root.join("app/services/code_generators"))
        .to_s.delete_suffix(".rb")
    end

    def save_generator(file_path, source)
      validation_errors = CodeGenerators::GeneratorValidator.validate_source(source)
      if validation_errors.any?
        @errors = validation_errors
        @source_code = source
        action = File.exist?(file_path) ? :edit : :new
        @kind = params[:kind] if action == :new
        render action, status: :unprocessable_entity
        return
      end

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, source)
      Rails.autoloaders.main.reload
      CodeGenerators::GeneratorRegistry.instance.reload!

      yield
    end

    def template_for(kind)
      dir = kind == "element_type" ? "ElementTypes" : "StepActions"
      <<~RUBY
        # frozen_string_literal: true

        class CodeGenerators::#{dir}::MyGenerator < CodeGenerators::BaseGenerator
          generator_metadata do
            description "TODO: describe what this generator does"
            category    :uncategorized
            version     "1.0.0"
          end

          input_schema  # TODO: declare ctx keys read
          output_schema # TODO: declare ctx keys written

          def generate
            # TODO: implement code generation
            "true"
          end

          def validate_config(config)
            [] # Return array of error strings
          end

          def example_output
            "true"
          end
        end
      RUBY
    end
  end
end
```

- [ ] **Step 3: Write controller spec**

```ruby
# spec/controllers/admin/code_generators_controller_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CodeGeneratorsController, type: :controller do
  # Skip auth for these tests (test the controller logic, not auth)
  before do
    allow(controller).to receive(:require_admin_role!).and_return(true)
    allow(controller).to receive(:set_current_customer).and_return(true)
  end

  describe "GET #index" do
    it "returns success" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "assigns step_actions and element_types" do
      get :index
      expect(assigns(:step_actions)).to be_a(Hash)
      expect(assigns(:element_types)).to be_a(Hash)
    end
  end

  describe "GET #show" do
    it "returns success for existing generator" do
      get :show, params: { path: "step_actions/new_model_generator" }
      expect(response).to have_http_status(:success)
      expect(assigns(:source_code)).to be_present
    end
  end

  describe "GET #new" do
    it "returns success" do
      get :new, params: { kind: "step_action" }
      expect(response).to have_http_status(:success)
      expect(assigns(:source_code)).to include("BaseGenerator")
    end
  end

  describe "POST #validate" do
    it "returns valid for good source" do
      source = <<~RUBY
        class CodeGenerators::StepActions::TestValidGenerator < CodeGenerators::BaseGenerator
          generator_metadata do
            description "Test"
            category :test
            version "1.0.0"
          end
          def generate; "true"; end
          def validate_config(config); []; end
        end
      RUBY

      post :validate, params: { path: "step_actions/new_model_generator", source_code: source }
      json = JSON.parse(response.body)
      expect(json["valid"]).to be true
    end

    it "returns errors for bad syntax" do
      post :validate, params: { path: "step_actions/new_model_generator", source_code: "def foo(" }
      json = JSON.parse(response.body)
      expect(json["valid"]).to be false
      expect(json["errors"]).not_to be_empty
    end
  end

  describe "GET #preview" do
    it "returns example_output" do
      get :preview, params: { path: "step_actions/new_model_generator" }
      json = JSON.parse(response.body)
      expect(json["example_output"]).to be_present
    end
  end
end
```

- [ ] **Step 4: Run controller spec**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb -fd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb \
        app/controllers/admin/code_generators_controller.rb \
        spec/controllers/admin/code_generators_controller_spec.rb
git commit -m "feat: add admin code generators controller with CRUD + validate + preview"
```

---

## Task 19: ViewComponents — Index + Show

**Files:**
- Create: `app/components/admin/code_generators/index_component.rb`
- Create: `app/components/admin/code_generators/index_component.html.erb`
- Create: `app/components/admin/code_generators/show_component.rb`
- Create: `app/components/admin/code_generators/show_component.html.erb`
- Create: `app/views/admin/code_generators/index.html.erb`
- Create: `app/views/admin/code_generators/show.html.erb`

- [ ] **Step 1: Create IndexComponent**

```ruby
# app/components/admin/code_generators/index_component.rb
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class IndexComponent < ApplicationComponent
      def initialize(step_actions:, element_types:)
        @step_actions = step_actions
        @element_types = element_types
      end

      def grouped_step_actions
        @step_actions.group_by { |_name, klass| klass._metadata[:category] }
      end

      def grouped_element_types
        @element_types.group_by { |_name, klass| klass._metadata[:category] }
      end

      def generator_path(name, kind)
        dir = kind == :element_type ? "element_types" : "step_actions"
        "/admin/code_generators/#{dir}%2F#{name}_generator"
      end
    end
  end
end
```

```erb
<%# app/components/admin/code_generators/index_component.html.erb %>
<div class="max-w-7xl mx-auto px-4 py-8">
  <div class="flex items-center justify-between mb-8">
    <h1 class="text-2xl font-bold text-gray-900">Code Generators</h1>
    <div class="relative" data-controller="dropdown">
      <button data-action="click->dropdown#toggle" class="inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700">
        New Generator
        <svg class="ml-2 w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>
      </button>
      <div data-dropdown-target="menu" class="hidden absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg border z-10">
        <%= link_to "Step Action", new_admin_code_generator_path(kind: "step_action"), class: "block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
        <%= link_to "Element Type", new_admin_code_generator_path(kind: "element_type"), class: "block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
      </div>
    </div>
  </div>

  <%# Element Types Section %>
  <h2 class="text-lg font-semibold text-gray-800 mb-4">Element Types (<%= @element_types.size %>)</h2>
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
    <% @element_types.each do |name, klass| %>
      <%= link_to generator_path(name, :element_type), class: "block p-4 bg-white rounded-lg border border-gray-200 hover:border-indigo-300 hover:shadow-sm transition" do %>
        <div class="flex items-center justify-between mb-2">
          <h3 class="font-medium text-gray-900"><%= name.titleize %></h3>
          <span class="text-xs px-2 py-1 rounded-full bg-blue-100 text-blue-800"><%= klass._metadata[:category] %></span>
        </div>
        <p class="text-sm text-gray-600"><%= klass._metadata[:description] %></p>
        <p class="text-xs text-gray-400 mt-2">v<%= klass._metadata[:version] %></p>
      <% end %>
    <% end %>
  </div>

  <%# Step Actions Section %>
  <h2 class="text-lg font-semibold text-gray-800 mb-4">Step Actions (<%= @step_actions.size %>)</h2>
  <% grouped_step_actions.each do |category, generators| %>
    <h3 class="text-sm font-medium text-gray-500 uppercase tracking-wide mb-2 mt-4"><%= category %> (<%= generators.size %>)</h3>
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-4">
      <% generators.each do |name, klass| %>
        <%= link_to generator_path(name, :step_action), class: "block p-4 bg-white rounded-lg border border-gray-200 hover:border-indigo-300 hover:shadow-sm transition" do %>
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-medium text-gray-900"><%= name.titleize %></h3>
            <span class="text-xs px-2 py-1 rounded-full bg-green-100 text-green-800"><%= klass._metadata[:category] %></span>
          </div>
          <p class="text-sm text-gray-600"><%= klass._metadata[:description] %></p>
          <p class="text-xs text-gray-400 mt-2">v<%= klass._metadata[:version] %></p>
        <% end %>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Create ShowComponent**

```ruby
# app/components/admin/code_generators/show_component.rb
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class ShowComponent < ApplicationComponent
      def initialize(generator_class:, source_code:, path:)
        @generator_class = generator_class
        @source_code = source_code
        @path = path
      end

      def metadata
        @generator_class&._metadata || {}
      end

      def input_keys
        @generator_class&._input_keys || []
      end

      def output_keys
        @generator_class&._output_keys || []
      end

      def edit_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/edit"
      end

      def delete_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}"
      end
    end
  end
end
```

```erb
<%# app/components/admin/code_generators/show_component.html.erb %>
<div class="max-w-5xl mx-auto px-4 py-8">
  <%= link_to "Back to Generators", admin_code_generators_path, class: "text-sm text-indigo-600 hover:text-indigo-800 mb-4 inline-block" %>

  <div class="bg-white rounded-lg border border-gray-200 p-6 mb-6">
    <div class="flex items-center justify-between mb-4">
      <div>
        <h1 class="text-2xl font-bold text-gray-900"><%= @generator_class&.generator_name&.titleize %></h1>
        <p class="text-gray-600 mt-1"><%= metadata[:description] %></p>
      </div>
      <div class="flex items-center gap-2">
        <span class="text-xs px-2 py-1 rounded-full bg-blue-100 text-blue-800"><%= metadata[:category] %></span>
        <span class="text-xs text-gray-400">v<%= metadata[:version] %></span>
      </div>
    </div>

    <div class="flex gap-6 mb-4">
      <div>
        <h3 class="text-xs font-medium text-gray-500 uppercase">Input Schema</h3>
        <div class="flex gap-1 mt-1">
          <% input_keys.each do |key| %>
            <span class="text-xs px-2 py-1 bg-yellow-50 text-yellow-700 rounded"><%= key %></span>
          <% end %>
          <% if input_keys.empty? %><span class="text-xs text-gray-400">none</span><% end %>
        </div>
      </div>
      <div>
        <h3 class="text-xs font-medium text-gray-500 uppercase">Output Schema</h3>
        <div class="flex gap-1 mt-1">
          <% output_keys.each do |key| %>
            <span class="text-xs px-2 py-1 bg-emerald-50 text-emerald-700 rounded"><%= key %></span>
          <% end %>
          <% if output_keys.empty? %><span class="text-xs text-gray-400">none</span><% end %>
        </div>
      </div>
    </div>

    <div class="flex gap-2">
      <%= link_to "Edit", edit_path, class: "inline-flex items-center px-3 py-1.5 bg-indigo-600 text-white text-sm rounded hover:bg-indigo-700" %>
      <%= button_to "Delete", delete_path, method: :delete, data: { turbo_confirm: "Delete this generator?" }, class: "inline-flex items-center px-3 py-1.5 bg-red-600 text-white text-sm rounded hover:bg-red-700" %>
    </div>
  </div>

  <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
    <div class="px-4 py-2 bg-gray-50 border-b border-gray-200">
      <h2 class="text-sm font-medium text-gray-700">Source Code</h2>
    </div>
    <pre class="p-4 text-sm font-mono text-gray-800 overflow-x-auto leading-relaxed"><code><%= @source_code %></code></pre>
  </div>
</div>
```

- [ ] **Step 3: Create view templates**

```erb
<%# app/views/admin/code_generators/index.html.erb %>
<%= render Admin::CodeGenerators::IndexComponent.new(
  step_actions: @step_actions,
  element_types: @element_types
) %>
```

```erb
<%# app/views/admin/code_generators/show.html.erb %>
<%= render Admin::CodeGenerators::ShowComponent.new(
  generator_class: @generator_class,
  source_code: @source_code,
  path: params[:path]
) %>
```

- [ ] **Step 4: Commit**

```bash
git add app/components/admin/code_generators/ \
        app/views/admin/code_generators/
git commit -m "feat: add index and show ViewComponents for admin code generators"
```

---

## Task 20: ViewComponents — Form + Editor

**Files:**
- Create: `app/components/admin/code_generators/form_component.rb`
- Create: `app/components/admin/code_generators/form_component.html.erb`
- Create: `app/views/admin/code_generators/new.html.erb`
- Create: `app/views/admin/code_generators/edit.html.erb`
- Create: `app/javascript/controllers/code_editor_controller.js`

- [ ] **Step 1: Create FormComponent**

```ruby
# app/components/admin/code_generators/form_component.rb
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class FormComponent < ApplicationComponent
      def initialize(source_code:, kind: nil, file_name: nil, errors: [], path: nil)
        @source_code = source_code
        @kind = kind
        @file_name = file_name
        @errors = errors
        @path = path
      end

      def creating?
        @path.nil?
      end

      def form_url
        creating? ? admin_code_generators_path : "/admin/code_generators/#{@path.gsub('/', '%2F')}"
      end

      def form_method
        creating? ? :post : :patch
      end

      def validate_url
        return nil if creating?
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/validate"
      end
    end
  end
end
```

```erb
<%# app/components/admin/code_generators/form_component.html.erb %>
<div class="max-w-5xl mx-auto px-4 py-8">
  <%= link_to "Back to Generators", admin_code_generators_path, class: "text-sm text-indigo-600 hover:text-indigo-800 mb-4 inline-block" %>

  <h1 class="text-2xl font-bold text-gray-900 mb-6"><%= creating? ? "New Generator" : "Edit Generator" %></h1>

  <% if @errors.any? %>
    <div class="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg">
      <h3 class="text-sm font-medium text-red-800">Validation errors:</h3>
      <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
        <% @errors.each do |error| %>
          <li><%= error %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%= form_with url: form_url, method: form_method, data: { controller: "code-editor", code_editor_validate_url_value: validate_url } do |f| %>
    <% if creating? %>
      <div class="grid grid-cols-2 gap-4 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Kind</label>
          <select name="kind" class="w-full rounded-md border-gray-300 shadow-sm text-sm focus:ring-indigo-500 focus:border-indigo-500">
            <option value="step_action" <%= "selected" if @kind == "step_action" %>>Step Action</option>
            <option value="element_type" <%= "selected" if @kind == "element_type" %>>Element Type</option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">File Name</label>
          <input type="text" name="file_name" value="<%= @file_name %>" placeholder="my_action" class="w-full rounded-md border-gray-300 shadow-sm text-sm focus:ring-indigo-500 focus:border-indigo-500">
          <p class="text-xs text-gray-500 mt-1">Will be suffixed with _generator.rb</p>
        </div>
      </div>
    <% end %>

    <div class="mb-4">
      <div class="flex items-center justify-between mb-1">
        <label class="block text-sm font-medium text-gray-700">Source Code</label>
        <% if validate_url %>
          <button type="button" data-action="click->code-editor#validate" class="text-xs px-3 py-1 bg-gray-100 text-gray-700 rounded hover:bg-gray-200">
            Validate
          </button>
        <% end %>
      </div>
      <div data-code-editor-target="validationResult" class="hidden mb-2 p-2 text-sm rounded"></div>
      <textarea name="source_code" rows="30" data-code-editor-target="editor" class="w-full font-mono text-sm rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 leading-relaxed"><%= @source_code %></textarea>
    </div>

    <div class="flex gap-2">
      <button type="submit" class="inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700">
        <%= creating? ? "Create Generator" : "Save Changes" %>
      </button>
      <%= link_to "Cancel", admin_code_generators_path, class: "inline-flex items-center px-4 py-2 bg-white text-gray-700 text-sm font-medium rounded-md border border-gray-300 hover:bg-gray-50" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Create Stimulus controller for editor**

```javascript
// app/javascript/controllers/code_editor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "validationResult"]
  static values = { validateUrl: String }

  async validate() {
    if (!this.validateUrlValue) return

    const source = this.editorTarget.value
    const token = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(this.validateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": token
        },
        body: new URLSearchParams({ source_code: source })
      })

      const data = await response.json()
      const el = this.validationResultTarget
      el.classList.remove("hidden")

      if (data.valid) {
        el.className = "mb-2 p-2 text-sm rounded bg-green-50 text-green-800"
        el.textContent = "Valid — all checks passed"
      } else {
        el.className = "mb-2 p-2 text-sm rounded bg-red-50 text-red-800"
        el.innerHTML = data.errors.map(e => `• ${e}`).join("<br>")
      }
    } catch (err) {
      const el = this.validationResultTarget
      el.classList.remove("hidden")
      el.className = "mb-2 p-2 text-sm rounded bg-yellow-50 text-yellow-800"
      el.textContent = `Validation request failed: ${err.message}`
    }
  }
}
```

- [ ] **Step 3: Create view templates for new and edit**

```erb
<%# app/views/admin/code_generators/new.html.erb %>
<%= render Admin::CodeGenerators::FormComponent.new(
  source_code: @source_code,
  kind: @kind,
  errors: @errors || []
) %>
```

```erb
<%# app/views/admin/code_generators/edit.html.erb %>
<%= render Admin::CodeGenerators::FormComponent.new(
  source_code: @source_code,
  path: params[:path],
  errors: @errors || []
) %>
```

- [ ] **Step 4: Commit**

```bash
git add app/components/admin/code_generators/form_component.rb \
        app/components/admin/code_generators/form_component.html.erb \
        app/views/admin/code_generators/new.html.erb \
        app/views/admin/code_generators/edit.html.erb \
        app/javascript/controllers/code_editor_controller.js
git commit -m "feat: add form ViewComponent and Stimulus editor for code generators"
```

---

## Task 21: Add Admin Link to Navigation

**Files:**
- Modify: `app/views/layouts/application.html.erb` (add link to code generators admin)

- [ ] **Step 1: Add admin link**

In the application layout, near the existing admin users link, add a link to the code generators admin. Find the existing admin link block and add alongside it:

```erb
<%= link_to "Code Generators", admin_code_generators_path, class: "text-sm text-gray-600 hover:text-gray-900" %>
```

- [ ] **Step 2: Verify the admin pages work**

Run: `bundle exec rails server` and manually visit:
- `/admin/code_generators` — should show index with all generators
- `/admin/code_generators/step_actions%2Fnew_model_generator` — should show generator details
- `/admin/code_generators/step_actions%2Fnew_model_generator/edit` — should show editor

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: add code generators admin link to navigation"
```
