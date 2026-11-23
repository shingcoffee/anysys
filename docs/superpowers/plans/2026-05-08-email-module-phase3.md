# Email Module Implementation Plan - Phase 3: Admin UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Build admin UI controllers and views for templates, messages, subscribers, lists, and campaigns

**Architecture:** Tenant-scoped admin controllers under `email/admin/` and `email_campaigns/admin/`. Reuse existing patterns: `EntriesTableComponent` for index pages, `BreadcrumbsComponent` for navigation, `set_tenant_from_route_params` for tenant resolution. Public unsubscribe endpoint outside auth.

**Tech Stack:** Rails 8.1 controllers, ViewComponent, TailwindCSS, StimulusJS

---

## File Structure

```
app/controllers/
├── email/
│   └── admin/
│       ├── templates_controller.rb
│       └── messages_controller.rb
├── email_campaigns/
│   ├── admin/
│   │   ├── subscribers_controller.rb
│   │   ├── lists_controller.rb
│   │   └── campaigns_controller.rb
│   └── unsubscribes_controller.rb

app/views/
├── email/
│   └── admin/
│       ├── templates/
│       │   ├── index.html.erb
│       │   ├── new.html.erb
│       │   ├── edit.html.erb
│       │   └── _form.html.erb
│       └── messages/
│           ├── index.html.erb
│           └── show.html.erb
├── email_campaigns/
│   ├── admin/
│   │   ├── subscribers/
│   │   │   ├── index.html.erb
│   │   │   ├── new.html.erb
│   │   │   ├── edit.html.erb
│   │   │   ├── show.html.erb
│   │   │   └── _form.html.erb
│   │   ├── lists/
│   │   │   ├── index.html.erb
│   │   │   ├── new.html.erb
│   │   │   ├── edit.html.erb
│   │   │   ├── show.html.erb
│   │   │   └── _form.html.erb
│   │   └── campaigns/
│   │       ├── index.html.erb
│   │       ├── new.html.erb
│   │       ├── edit.html.erb
│   │       ├── show.html.erb
│   │       └── _form.html.erb
│   └── unsubscribes/
│       └── show.html.erb

config/routes.rb (modify)
```

---

### Task 1: Add Email and EmailCampaigns Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Find tenant-scoped section**

The file has a `scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do` block. Add the email routes inside that block, after the existing modules.

- [ ] **Step 2: Add routes inside tenant scope**

```ruby
    scope "email", as: :email do
      namespace :admin, module: "email/admin" do
        resources :templates
        resources :messages, only: %i[index show]
      end
    end

    scope "email_campaigns", as: :email_campaigns do
      namespace :admin, module: "email_campaigns/admin" do
        resources :subscribers
        resources :lists
        resources :campaigns do
          member do
            post :send_now
            post :pause
            post :resume
            post :cancel
          end
        end
      end
    end
```

- [ ] **Step 3: Add public unsubscribe route OUTSIDE tenant scope**

After the `scope "/:customer_id"...end` block, add:

```ruby
  # Public unsubscribe (no auth, no tenant scope)
  get  "/unsubscribe/:token", to: "email_campaigns/unsubscribes#show",   as: :email_unsubscribe
  post "/unsubscribe/:token", to: "email_campaigns/unsubscribes#create", as: :email_unsubscribe_create
```

- [ ] **Step 4: Verify routes load**

Run: `cd /home/ec2-user/anysys && bin/rails routes | grep -E "email|unsubscribe" | head -30`

Expected: see all email/email_campaigns routes listed.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb
git commit -m "feat(email): add email and email_campaigns admin routes"
```

---

### Task 2: Email Templates Admin Controller + Views

**Files:**
- Create: `app/controllers/email/admin/templates_controller.rb`
- Create: `app/views/email/admin/templates/index.html.erb`
- Create: `app/views/email/admin/templates/new.html.erb`
- Create: `app/views/email/admin/templates/edit.html.erb`
- Create: `app/views/email/admin/templates/_form.html.erb`
- Create: `spec/requests/email/admin/templates_spec.rb`

- [ ] **Step 1: Write request spec**

```ruby
# spec/requests/email/admin/templates_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email::Admin::Templates", type: :request do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer, role: "admin") }

  before do
    sign_in user
    Current.customer = customer
  end

  describe "GET /:customer_id/email/admin/templates" do
    let!(:template) { create(:email_template, customer: customer, name: "Welcome") }

    it "renders template list" do
      get "/#{customer.id}/email/admin/templates"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Welcome")
    end
  end

  describe "POST /:customer_id/email/admin/templates" do
    let(:valid_params) do
      {
        email_template: {
          key:           "welcome",
          name:          "Welcome",
          subject:       "Hi {{name}}",
          body_html:     "<p>Hello {{name}}</p>",
          template_type: "transactional",
          editor_type:   "code",
          status:        "active",
          variables:     "name"
        }
      }
    end

    it "creates a template" do
      expect {
        post "/#{customer.id}/email/admin/templates", params: valid_params
      }.to change(EmailTemplate, :count).by(1)

      expect(response).to redirect_to("/#{customer.id}/email/admin/templates")
    end
  end

  describe "PATCH /:customer_id/email/admin/templates/:id" do
    let!(:template) { create(:email_template, customer: customer) }

    it "updates the template" do
      patch "/#{customer.id}/email/admin/templates/#{template.id}",
            params: { email_template: { name: "Updated" } }

      expect(template.reload.name).to eq("Updated")
    end
  end

  describe "DELETE /:customer_id/email/admin/templates/:id" do
    let!(:template) { create(:email_template, customer: customer) }

    it "destroys the template" do
      expect {
        delete "/#{customer.id}/email/admin/templates/#{template.id}"
      }.to change(EmailTemplate, :count).by(-1)
    end
  end
end
```

- [ ] **Step 2: Create controller**

```ruby
# app/controllers/email/admin/templates_controller.rb
# frozen_string_literal: true

module Email
  module Admin
    class TemplatesController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_admin_or_owner!
      before_action :load_template, only: %i[edit update destroy]

      def index
        columns = [
          { key: :name,          label: "Name",   searchable: true, sortable: true },
          { key: :key,           label: "Key" },
          { key: :template_type, label: "Type" },
          { key: :status,        label: "Status", sortable: true },
          { key: :updated_at,    label: "Updated", sortable: true }
        ]
        result = ModuleEntriesResolver.call(
          scope:   EmailTemplate.for_current_customer.order(updated_at: :desc),
          columns: columns,
          params:  params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        )
        @columns    = columns
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def new
        @template = EmailTemplate.new(customer: current_customer, status: "draft", editor_type: "code", template_type: "transactional", variables: [])
      end

      def create
        @template = EmailTemplate.new(template_params.merge(customer: current_customer))
        if @template.save
          redirect_to "/#{current_customer.id}/email/admin/templates", notice: "Template created"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @template.update(template_params)
          redirect_to "/#{current_customer.id}/email/admin/templates", notice: "Template updated"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @template.destroy
        redirect_to "/#{current_customer.id}/email/admin/templates", notice: "Template deleted"
      rescue ActiveRecord::DeleteRestrictionError
        redirect_to "/#{current_customer.id}/email/admin/templates",
                    alert: "Cannot delete template — emails reference it"
      end

      private

      def load_template
        @template = EmailTemplate.for_current_customer.find(params[:id])
      end

      def template_params
        permitted = params.require(:email_template).permit(
          :key, :name, :subject, :body_html, :body_text,
          :template_type, :editor_type, :status
        )

        # Variables come in as comma-separated string from form, convert to array
        if params[:email_template][:variables].is_a?(String)
          permitted[:variables] = params[:email_template][:variables]
                                    .split(",").map(&:strip).reject(&:empty?)
        end

        permitted
      end

      def current_dashboard_section = :modules
      helper_method :current_dashboard_section
    end
  end
end
```

- [ ] **Step 3: Create views**

```erb
<%# app/views/email/admin/templates/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email",   path: nil },
  { label: "Templates", path: nil }
]) %>

<div class="flex justify-between items-center mb-6">
  <h1 class="text-2xl font-semibold text-gray-900">Email Templates</h1>
  <%= link_to "New Template",
        "/#{current_customer.id}/email/admin/templates/new",
        class: "inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
</div>

<%= render EntriesTableComponent.new(
  title:      nil,
  columns:    @columns,
  rows:       @rows,
  pagination: @pagination,
  row_path:   ->(r) { "/#{current_customer.id}/email/admin/templates/#{r.id}/edit" },
  params:     params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

```erb
<%# app/views/email/admin/templates/new.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email",   path: nil },
  { label: "Templates", path: "/#{current_customer.id}/email/admin/templates" },
  { label: "New", path: nil }
]) %>

<div class="max-w-3xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">New Email Template</h1>
  <%= render "form", template: @template, url: "/#{current_customer.id}/email/admin/templates", method: :post %>
</div>
```

```erb
<%# app/views/email/admin/templates/edit.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email",   path: nil },
  { label: "Templates", path: "/#{current_customer.id}/email/admin/templates" },
  { label: @template.name, path: nil }
]) %>

<div class="max-w-3xl">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-semibold text-gray-900">Edit Template</h1>
    <%= button_to "Delete",
          "/#{current_customer.id}/email/admin/templates/#{@template.id}",
          method: :delete,
          data: { turbo_confirm: "Are you sure?" },
          class: "px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700" %>
  </div>
  <%= render "form", template: @template, url: "/#{current_customer.id}/email/admin/templates/#{@template.id}", method: :patch %>
</div>
```

```erb
<%# app/views/email/admin/templates/_form.html.erb %>
<%= form_with model: template, url: url, method: method, local: true, class: "space-y-6" do |f| %>
  <% if template.errors.any? %>
    <div class="rounded-md bg-red-50 p-4">
      <h3 class="text-sm font-medium text-red-800">Please fix the following errors:</h3>
      <ul class="mt-2 list-disc list-inside text-sm text-red-700">
        <% template.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :name, class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_field :name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
    <div>
      <%= f.label :key, class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_field :key, placeholder: "lowercase_with_underscores", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
  </div>

  <div>
    <%= f.label :subject, class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_field :subject, placeholder: "Welcome {{first_name}}!", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    <p class="mt-1 text-xs text-gray-500">Use {{variable}} for dynamic values</p>
  </div>

  <div>
    <%= f.label :body_html, "HTML Body", class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_area :body_html, rows: 10, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 font-mono text-sm" %>
  </div>

  <div>
    <%= f.label :body_text, "Plain Text Body (optional, auto-generated if blank)", class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_area :body_text, rows: 4, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 font-mono text-sm" %>
  </div>

  <div>
    <%= f.label :variables, "Variables (comma-separated)", class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_field :variables, value: Array(template.variables).join(", "), placeholder: "first_name, order_id", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div class="grid grid-cols-3 gap-4">
    <div>
      <%= f.label :template_type, "Type", class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :template_type, EmailTemplate::TEMPLATE_TYPES.map { |t| [t.titleize, t] }, {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
    <div>
      <%= f.label :editor_type, "Editor", class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :editor_type, EmailTemplate::EDITOR_TYPES.map { |t| [t.titleize.gsub("_", " "), t] }, {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
    <div>
      <%= f.label :status, class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :status, EmailTemplate::STATUSES.map { |s| [s.titleize, s] }, {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
  </div>

  <div class="flex justify-end gap-3">
    <%= link_to "Cancel", "/#{current_customer.id}/email/admin/templates", class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
    <%= f.submit (template.persisted? ? "Update" : "Create"), class: "px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
  </div>
<% end %>
```

- [ ] **Step 4: Run tests**

Run: `cd /home/ec2-user/anysys && bundle exec rspec spec/requests/email/admin/templates_spec.rb`

If specs fail due to user role/devise setup not matching the project's actual auth patterns, examine `app/controllers/sms/admin/messages_controller.rb` and existing request specs to match patterns.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/email/admin/templates_controller.rb app/views/email/admin/templates/ spec/requests/email/admin/templates_spec.rb
git commit -m "feat(email): add admin templates CRUD UI"
```

---

### Task 3: Email Messages Admin Controller + Views

**Files:**
- Create: `app/controllers/email/admin/messages_controller.rb`
- Create: `app/views/email/admin/messages/index.html.erb`
- Create: `app/views/email/admin/messages/show.html.erb`

Read-only audit log following the pattern of `app/controllers/sms/admin/messages_controller.rb`.

- [ ] **Step 1: Create controller**

```ruby
# app/controllers/email/admin/messages_controller.rb
# frozen_string_literal: true

module Email
  module Admin
    class MessagesController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_admin_or_owner!

      def index
        columns = [
          { key: :created_at,   label: "At",       sortable: true },
          { key: :to,           label: "To",       searchable: true },
          { key: :subject,      label: "Subject",  searchable: true },
          { key: :message_type, label: "Type" },
          { key: :status,       label: "Status",   sortable: true }
        ]
        result = ModuleEntriesResolver.call(
          scope:   EmailMessage.for_current_customer.includes(:email_template).order(created_at: :desc),
          columns: columns,
          params:  params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        )
        @columns    = columns
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def show
        @message = EmailMessage.for_current_customer.find(params[:id])
      end

      private

      def current_dashboard_section = :modules
      helper_method :current_dashboard_section
    end
  end
end
```

- [ ] **Step 2: Create views**

```erb
<%# app/views/email/admin/messages/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email",   path: nil },
  { label: "Messages", path: nil }
]) %>

<h1 class="text-2xl font-semibold text-gray-900 mb-6">Email Messages</h1>

<%= render EntriesTableComponent.new(
  title:      nil,
  columns:    @columns,
  rows:       @rows,
  pagination: @pagination,
  row_path:   ->(r) { "/#{current_customer.id}/email/admin/messages/#{r.id}" },
  params:     params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

```erb
<%# app/views/email/admin/messages/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email",   path: nil },
  { label: "Messages", path: "/#{current_customer.id}/email/admin/messages" },
  { label: "##{@message.id}", path: nil }
]) %>

<div class="max-w-4xl space-y-6">
  <div class="flex items-center gap-3 mb-2">
    <h1 class="text-2xl font-semibold text-gray-900">Message #<%= @message.id %></h1>
    <% status_color = case @message.status
       when "sent", "delivered" then "bg-green-100 text-green-800"
       when "failed", "bounced" then "bg-red-100 text-red-800"
       when "queued", "pending" then "bg-yellow-100 text-yellow-800"
       else "bg-gray-100 text-gray-800"
       end %>
    <span class="px-2 py-1 text-xs font-medium rounded-full <%= status_color %>"><%= @message.status %></span>
  </div>

  <dl class="bg-white shadow rounded-lg divide-y divide-gray-200">
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">To</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @message.to %></dd>
    </div>
    <% if @message.cc.present? %>
      <div class="px-4 py-3 grid grid-cols-3 gap-4">
        <dt class="text-sm font-medium text-gray-500">CC</dt>
        <dd class="text-sm text-gray-900 col-span-2"><%= @message.cc %></dd>
      </div>
    <% end %>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">From</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @message.from %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Subject</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @message.subject %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Type</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @message.message_type %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Sent At</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @message.sent_at&.to_fs(:long) || "—" %></dd>
    </div>
    <% if @message.failure_message.present? %>
      <div class="px-4 py-3 grid grid-cols-3 gap-4">
        <dt class="text-sm font-medium text-gray-500">Failure</dt>
        <dd class="text-sm text-red-700 col-span-2">
          <strong><%= @message.failure_code %></strong>: <%= @message.failure_message %>
        </dd>
      </div>
    <% end %>
  </dl>

  <div class="bg-white shadow rounded-lg overflow-hidden">
    <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
      <h2 class="text-sm font-medium text-gray-700">HTML Body</h2>
    </div>
    <iframe srcdoc="<%= @message.body_html %>" class="w-full min-h-[400px] bg-white"></iframe>
  </div>

  <% if @message.body_text.present? %>
    <div class="bg-white shadow rounded-lg overflow-hidden">
      <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
        <h2 class="text-sm font-medium text-gray-700">Plain Text</h2>
      </div>
      <pre class="p-4 text-sm text-gray-900 whitespace-pre-wrap font-mono"><%= @message.body_text %></pre>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Verify by hitting the route**

Run: `cd /home/ec2-user/anysys && bin/rails routes | grep "email/admin/messages"`

Expected: `GET /:customer_id/email/admin/messages` and `GET /:customer_id/email/admin/messages/:id`

- [ ] **Step 4: Commit**

```bash
git add app/controllers/email/admin/messages_controller.rb app/views/email/admin/messages/
git commit -m "feat(email): add admin messages audit log UI"
```

---

### Task 4: Email Subscribers Admin Controller + Views

**Files:**
- Create: `app/controllers/email_campaigns/admin/subscribers_controller.rb`
- Create: `app/views/email_campaigns/admin/subscribers/index.html.erb`
- Create: `app/views/email_campaigns/admin/subscribers/new.html.erb`
- Create: `app/views/email_campaigns/admin/subscribers/edit.html.erb`
- Create: `app/views/email_campaigns/admin/subscribers/show.html.erb`
- Create: `app/views/email_campaigns/admin/subscribers/_form.html.erb`

- [ ] **Step 1: Create controller**

```ruby
# app/controllers/email_campaigns/admin/subscribers_controller.rb
# frozen_string_literal: true

module EmailCampaigns
  module Admin
    class SubscribersController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_admin_or_owner!
      before_action :load_subscriber, only: %i[show edit update destroy]

      def index
        columns = [
          { key: :email,         label: "Email",      searchable: true, sortable: true },
          { key: :full_name,     label: "Name" },
          { key: :status,        label: "Status",     sortable: true },
          { key: :subscribed_at, label: "Subscribed", sortable: true }
        ]
        result = ModuleEntriesResolver.call(
          scope:   EmailSubscriber.for_current_customer.order(created_at: :desc),
          columns: columns,
          params:  params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        )
        @columns    = columns
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def show
      end

      def new
        @subscriber = EmailSubscriber.new(customer: current_customer, status: "active", tags: [])
      end

      def create
        @subscriber = EmailSubscriber.new(subscriber_params.merge(customer: current_customer))
        if @subscriber.save
          redirect_to "/#{current_customer.id}/email_campaigns/admin/subscribers", notice: "Subscriber added"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @subscriber.update(subscriber_params)
          redirect_to "/#{current_customer.id}/email_campaigns/admin/subscribers/#{@subscriber.id}", notice: "Subscriber updated"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @subscriber.destroy
        redirect_to "/#{current_customer.id}/email_campaigns/admin/subscribers", notice: "Subscriber deleted"
      end

      private

      def load_subscriber
        @subscriber = EmailSubscriber.for_current_customer.find(params[:id])
      end

      def subscriber_params
        permitted = params.require(:email_subscriber).permit(:email, :first_name, :last_name, :status)

        if params[:email_subscriber][:tags].is_a?(String)
          permitted[:tags] = params[:email_subscriber][:tags]
                              .split(",").map(&:strip).reject(&:empty?)
        end

        permitted
      end

      def current_dashboard_section = :modules
      helper_method :current_dashboard_section
    end
  end
end
```

- [ ] **Step 2: Create views**

```erb
<%# app/views/email_campaigns/admin/subscribers/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Subscribers", path: nil }
]) %>

<div class="flex justify-between items-center mb-6">
  <h1 class="text-2xl font-semibold text-gray-900">Subscribers</h1>
  <%= link_to "New Subscriber",
        "/#{current_customer.id}/email_campaigns/admin/subscribers/new",
        class: "inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
</div>

<%= render EntriesTableComponent.new(
  title:      nil,
  columns:    @columns,
  rows:       @rows,
  pagination: @pagination,
  row_path:   ->(r) { "/#{current_customer.id}/email_campaigns/admin/subscribers/#{r.id}" },
  params:     params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

```erb
<%# app/views/email_campaigns/admin/subscribers/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Subscribers", path: "/#{current_customer.id}/email_campaigns/admin/subscribers" },
  { label: @subscriber.email, path: nil }
]) %>

<div class="max-w-3xl space-y-6">
  <div class="flex justify-between items-center">
    <div>
      <h1 class="text-2xl font-semibold text-gray-900"><%= @subscriber.full_name.presence || @subscriber.email %></h1>
      <p class="text-sm text-gray-600 mt-1"><%= @subscriber.email %></p>
    </div>
    <div class="flex gap-2">
      <%= link_to "Edit", "/#{current_customer.id}/email_campaigns/admin/subscribers/#{@subscriber.id}/edit",
            class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
      <%= button_to "Delete", "/#{current_customer.id}/email_campaigns/admin/subscribers/#{@subscriber.id}",
            method: :delete,
            data: { turbo_confirm: "Are you sure?" },
            class: "px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700" %>
    </div>
  </div>

  <dl class="bg-white shadow rounded-lg divide-y divide-gray-200">
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Status</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @subscriber.status %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Subscribed</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @subscriber.subscribed_at&.to_fs(:long) %></dd>
    </div>
    <% if @subscriber.unsubscribed_at %>
      <div class="px-4 py-3 grid grid-cols-3 gap-4">
        <dt class="text-sm font-medium text-gray-500">Unsubscribed</dt>
        <dd class="text-sm text-gray-900 col-span-2"><%= @subscriber.unsubscribed_at.to_fs(:long) %></dd>
      </div>
    <% end %>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Tags</dt>
      <dd class="text-sm text-gray-900 col-span-2">
        <% if @subscriber.tags.any? %>
          <% @subscriber.tags.each do |tag| %>
            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 mr-1"><%= tag %></span>
          <% end %>
        <% else %>
          <span class="text-gray-400">none</span>
        <% end %>
      </dd>
    </div>
  </dl>
</div>
```

```erb
<%# app/views/email_campaigns/admin/subscribers/new.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Subscribers", path: "/#{current_customer.id}/email_campaigns/admin/subscribers" },
  { label: "New", path: nil }
]) %>

<div class="max-w-2xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">New Subscriber</h1>
  <%= render "form", subscriber: @subscriber, url: "/#{current_customer.id}/email_campaigns/admin/subscribers", method: :post %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/subscribers/edit.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Subscribers", path: "/#{current_customer.id}/email_campaigns/admin/subscribers" },
  { label: @subscriber.email, path: "/#{current_customer.id}/email_campaigns/admin/subscribers/#{@subscriber.id}" },
  { label: "Edit", path: nil }
]) %>

<div class="max-w-2xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">Edit Subscriber</h1>
  <%= render "form", subscriber: @subscriber, url: "/#{current_customer.id}/email_campaigns/admin/subscribers/#{@subscriber.id}", method: :patch %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/subscribers/_form.html.erb %>
<%= form_with model: subscriber, url: url, method: method, local: true, class: "space-y-6" do |f| %>
  <% if subscriber.errors.any? %>
    <div class="rounded-md bg-red-50 p-4">
      <ul class="list-disc list-inside text-sm text-red-700">
        <% subscriber.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :email, class: "block text-sm font-medium text-gray-700" %>
    <%= f.email_field :email, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :first_name, class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_field :first_name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
    <div>
      <%= f.label :last_name, class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_field :last_name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
  </div>

  <div>
    <%= f.label :tags, "Tags (comma-separated)", class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_field :tags, value: Array(subscriber.tags).join(", "), placeholder: "premium, newsletter", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div>
    <%= f.label :status, class: "block text-sm font-medium text-gray-700" %>
    <%= f.select :status, EmailSubscriber::STATUSES.map { |s| [s.titleize, s] }, {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div class="flex justify-end gap-3">
    <%= link_to "Cancel", "/#{current_customer.id}/email_campaigns/admin/subscribers", class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
    <%= f.submit (subscriber.persisted? ? "Update" : "Create"), class: "px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
  </div>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/email_campaigns/admin/subscribers_controller.rb app/views/email_campaigns/admin/subscribers/
git commit -m "feat(email_campaigns): add admin subscribers CRUD UI"
```

---

### Task 5: Email Lists Admin Controller + Views

**Files:**
- Create: `app/controllers/email_campaigns/admin/lists_controller.rb`
- Create: `app/views/email_campaigns/admin/lists/index.html.erb`
- Create: `app/views/email_campaigns/admin/lists/new.html.erb`
- Create: `app/views/email_campaigns/admin/lists/edit.html.erb`
- Create: `app/views/email_campaigns/admin/lists/show.html.erb`
- Create: `app/views/email_campaigns/admin/lists/_form.html.erb`

- [ ] **Step 1: Create controller**

```ruby
# app/controllers/email_campaigns/admin/lists_controller.rb
# frozen_string_literal: true

module EmailCampaigns
  module Admin
    class ListsController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_admin_or_owner!
      before_action :load_list, only: %i[show edit update destroy]

      def index
        columns = [
          { key: :name,        label: "Name",   searchable: true, sortable: true },
          { key: :list_type,   label: "Type" },
          { key: :status,      label: "Status", sortable: true },
          { key: :updated_at,  label: "Updated", sortable: true }
        ]
        result = ModuleEntriesResolver.call(
          scope:   EmailList.for_current_customer.order(created_at: :desc),
          columns: columns,
          params:  params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        )
        @columns    = columns
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def show
        @subscriber_count = if @list.dynamic?
                              EmailCampaigns::SegmentEvaluator.call(
                                customer: current_customer,
                                rules:    @list.segment_rules
                              ).size
                            else
                              @list.email_subscribers.count
                            end
      end

      def new
        @list = EmailList.new(customer: current_customer, list_type: "static", status: "active", segment_rules: {})
      end

      def create
        @list = EmailList.new(list_params.merge(customer: current_customer))
        if @list.save
          redirect_to "/#{current_customer.id}/email_campaigns/admin/lists", notice: "List created"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @list.update(list_params)
          redirect_to "/#{current_customer.id}/email_campaigns/admin/lists/#{@list.id}", notice: "List updated"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @list.destroy
        redirect_to "/#{current_customer.id}/email_campaigns/admin/lists", notice: "List deleted"
      rescue ActiveRecord::DeleteRestrictionError
        redirect_to "/#{current_customer.id}/email_campaigns/admin/lists",
                    alert: "Cannot delete list — campaigns reference it"
      end

      private

      def load_list
        @list = EmailList.for_current_customer.find(params[:id])
      end

      def list_params
        permitted = params.require(:email_list).permit(:name, :description, :list_type, :status)

        if params[:email_list][:segment_rules_json].is_a?(String) && params[:email_list][:segment_rules_json].present?
          permitted[:segment_rules] = JSON.parse(params[:email_list][:segment_rules_json])
        end

        permitted
      rescue JSON::ParserError
        permitted[:segment_rules] = {}
        permitted
      end

      def current_dashboard_section = :modules
      helper_method :current_dashboard_section
    end
  end
end
```

- [ ] **Step 2: Create views**

```erb
<%# app/views/email_campaigns/admin/lists/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Lists", path: nil }
]) %>

<div class="flex justify-between items-center mb-6">
  <h1 class="text-2xl font-semibold text-gray-900">Email Lists</h1>
  <%= link_to "New List",
        "/#{current_customer.id}/email_campaigns/admin/lists/new",
        class: "inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
</div>

<%= render EntriesTableComponent.new(
  title:      nil,
  columns:    @columns,
  rows:       @rows,
  pagination: @pagination,
  row_path:   ->(r) { "/#{current_customer.id}/email_campaigns/admin/lists/#{r.id}" },
  params:     params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

```erb
<%# app/views/email_campaigns/admin/lists/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Lists", path: "/#{current_customer.id}/email_campaigns/admin/lists" },
  { label: @list.name, path: nil }
]) %>

<div class="max-w-4xl space-y-6">
  <div class="flex justify-between items-start">
    <div>
      <h1 class="text-2xl font-semibold text-gray-900"><%= @list.name %></h1>
      <p class="text-sm text-gray-600 mt-1"><%= @list.description %></p>
    </div>
    <div class="flex gap-2">
      <%= link_to "Edit", "/#{current_customer.id}/email_campaigns/admin/lists/#{@list.id}/edit",
            class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
    </div>
  </div>

  <div class="grid grid-cols-3 gap-4">
    <div class="bg-white shadow rounded-lg p-4">
      <p class="text-sm font-medium text-gray-500">Type</p>
      <p class="text-lg text-gray-900 mt-1"><%= @list.list_type.titleize %></p>
    </div>
    <div class="bg-white shadow rounded-lg p-4">
      <p class="text-sm font-medium text-gray-500">Status</p>
      <p class="text-lg text-gray-900 mt-1"><%= @list.status.titleize %></p>
    </div>
    <div class="bg-white shadow rounded-lg p-4">
      <p class="text-sm font-medium text-gray-500">Subscribers</p>
      <p class="text-lg text-gray-900 mt-1"><%= @subscriber_count %></p>
    </div>
  </div>

  <% if @list.dynamic? && @list.segment_rules.present? %>
    <div class="bg-white shadow rounded-lg p-4">
      <h2 class="text-sm font-medium text-gray-700 mb-2">Segment Rules</h2>
      <pre class="text-xs text-gray-700 bg-gray-50 p-3 rounded font-mono overflow-x-auto"><%= JSON.pretty_generate(@list.segment_rules) %></pre>
    </div>
  <% end %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/lists/new.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Lists", path: "/#{current_customer.id}/email_campaigns/admin/lists" },
  { label: "New", path: nil }
]) %>

<div class="max-w-3xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">New Email List</h1>
  <%= render "form", list: @list, url: "/#{current_customer.id}/email_campaigns/admin/lists", method: :post %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/lists/edit.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Lists", path: "/#{current_customer.id}/email_campaigns/admin/lists" },
  { label: @list.name, path: "/#{current_customer.id}/email_campaigns/admin/lists/#{@list.id}" },
  { label: "Edit", path: nil }
]) %>

<div class="max-w-3xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">Edit List</h1>
  <%= render "form", list: @list, url: "/#{current_customer.id}/email_campaigns/admin/lists/#{@list.id}", method: :patch %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/lists/_form.html.erb %>
<%= form_with model: list, url: url, method: method, local: true, class: "space-y-6" do |f| %>
  <% if list.errors.any? %>
    <div class="rounded-md bg-red-50 p-4">
      <ul class="list-disc list-inside text-sm text-red-700">
        <% list.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :name, class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_field :name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div>
    <%= f.label :description, class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_area :description, rows: 2, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :list_type, "Type", class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :list_type, EmailList::LIST_TYPES.map { |t| [t.titleize, t] }, {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      <p class="mt-1 text-xs text-gray-500">Static = manual subscriber selection. Dynamic = rule-based.</p>
    </div>
    <div>
      <%= f.label :status, class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :status, EmailList::STATUSES.map { |s| [s.titleize, s] }, {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
  </div>

  <div>
    <label class="block text-sm font-medium text-gray-700">Segment Rules (JSON, for dynamic lists)</label>
    <textarea name="email_list[segment_rules_json]" rows="8" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 font-mono text-xs" placeholder='{"match": "all", "conditions": [{"field": "tags", "operator": "contains", "value": "premium"}]}'><%= list.segment_rules.present? ? JSON.pretty_generate(list.segment_rules) : "" %></textarea>
    <p class="mt-1 text-xs text-gray-500">Operators: equals, not_equals, contains, not_contains, greater_than, less_than, after, before, is_blank, is_present</p>
  </div>

  <div class="flex justify-end gap-3">
    <%= link_to "Cancel", "/#{current_customer.id}/email_campaigns/admin/lists", class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
    <%= f.submit (list.persisted? ? "Update" : "Create"), class: "px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
  </div>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/email_campaigns/admin/lists_controller.rb app/views/email_campaigns/admin/lists/
git commit -m "feat(email_campaigns): add admin lists CRUD UI"
```

---

### Task 6: Email Campaigns Admin Controller + Views

**Files:**
- Create: `app/controllers/email_campaigns/admin/campaigns_controller.rb`
- Create: `app/views/email_campaigns/admin/campaigns/index.html.erb`
- Create: `app/views/email_campaigns/admin/campaigns/new.html.erb`
- Create: `app/views/email_campaigns/admin/campaigns/edit.html.erb`
- Create: `app/views/email_campaigns/admin/campaigns/show.html.erb`
- Create: `app/views/email_campaigns/admin/campaigns/_form.html.erb`

- [ ] **Step 1: Create controller**

```ruby
# app/controllers/email_campaigns/admin/campaigns_controller.rb
# frozen_string_literal: true

module EmailCampaigns
  module Admin
    class CampaignsController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_admin_or_owner!
      before_action :load_campaign, only: %i[show edit update destroy send_now pause resume cancel]

      def index
        columns = [
          { key: :name,         label: "Name",     searchable: true, sortable: true },
          { key: :status,       label: "Status",   sortable: true },
          { key: :scheduled_at, label: "Scheduled", sortable: true },
          { key: :sent_count,   label: "Sent" }
        ]
        scope = EmailCampaign.for_current_customer.order(created_at: :desc)
        result = ModuleEntriesResolver.call(
          scope:   scope,
          columns: columns,
          params:  params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        )
        @columns    = columns
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      def show
      end

      def new
        @campaign = EmailCampaign.new(customer: current_customer, status: "draft", timezone: "UTC", stats: {})
        load_form_collections
      end

      def create
        @campaign = EmailCampaign.new(campaign_params.merge(customer: current_customer))
        if @campaign.save
          redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", notice: "Campaign created"
        else
          load_form_collections
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        load_form_collections
      end

      def update
        if @campaign.update(campaign_params)
          redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", notice: "Campaign updated"
        else
          load_form_collections
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @campaign.destroy
        redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns", notice: "Campaign deleted"
      end

      def send_now
        @campaign.start!
        EmailCampaigns::SendCampaignJob.perform_later(@campaign.id)
        redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", notice: "Campaign sending"
      end

      def pause
        @campaign.pause!
        redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", notice: "Campaign paused"
      end

      def resume
        @campaign.resume!
        EmailCampaigns::SendCampaignJob.perform_later(@campaign.id)
        redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", notice: "Campaign resumed"
      end

      def cancel
        @campaign.cancel!
        redirect_to "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", notice: "Campaign cancelled"
      end

      private

      def load_campaign
        @campaign = EmailCampaign.for_current_customer.find(params[:id])
      end

      def load_form_collections
        @templates = EmailTemplate.for_current_customer.where(template_type: "marketing").or(EmailTemplate.for_current_customer.where(template_type: "transactional")).order(:name)
        @lists     = EmailList.for_current_customer.where(status: "active").order(:name)
      end

      def campaign_params
        params.require(:email_campaign).permit(
          :name, :email_template_id, :email_list_id,
          :scheduled_at, :recurrence_rule, :timezone
        )
      end

      def current_dashboard_section = :modules
      helper_method :current_dashboard_section
    end
  end
end
```

- [ ] **Step 2: Create views**

```erb
<%# app/views/email_campaigns/admin/campaigns/index.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Campaigns", path: nil }
]) %>

<div class="flex justify-between items-center mb-6">
  <h1 class="text-2xl font-semibold text-gray-900">Campaigns</h1>
  <%= link_to "New Campaign",
        "/#{current_customer.id}/email_campaigns/admin/campaigns/new",
        class: "inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
</div>

<%= render EntriesTableComponent.new(
  title:      nil,
  columns:    @columns,
  rows:       @rows,
  pagination: @pagination,
  row_path:   ->(r) { "/#{current_customer.id}/email_campaigns/admin/campaigns/#{r.id}" },
  params:     params.permit(:sort, :dir, :q, :page).to_h.symbolize_keys
) %>
```

```erb
<%# app/views/email_campaigns/admin/campaigns/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Campaigns", path: "/#{current_customer.id}/email_campaigns/admin/campaigns" },
  { label: @campaign.name, path: nil }
]) %>

<div class="max-w-4xl space-y-6">
  <div class="flex justify-between items-start">
    <div>
      <h1 class="text-2xl font-semibold text-gray-900"><%= @campaign.name %></h1>
      <% color = case @campaign.status
         when "sent" then "bg-green-100 text-green-800"
         when "sending" then "bg-blue-100 text-blue-800"
         when "scheduled" then "bg-yellow-100 text-yellow-800"
         when "paused" then "bg-orange-100 text-orange-800"
         when "cancelled" then "bg-red-100 text-red-800"
         else "bg-gray-100 text-gray-800"
         end %>
      <span class="mt-2 inline-block px-2 py-1 text-xs font-medium rounded-full <%= color %>"><%= @campaign.status %></span>
    </div>
    <div class="flex gap-2">
      <% if %w[draft scheduled].include?(@campaign.status) %>
        <%= link_to "Edit", "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}/edit",
              class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
        <%= button_to "Send Now", "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}/send_now",
              method: :post,
              data: { turbo_confirm: "Send this campaign now?" },
              class: "px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700" %>
      <% end %>
      <% if @campaign.status == "sending" %>
        <%= button_to "Pause", "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}/pause",
              method: :post,
              class: "px-4 py-2 bg-orange-500 text-white text-sm font-medium rounded-md hover:bg-orange-600" %>
      <% end %>
      <% if @campaign.status == "paused" %>
        <%= button_to "Resume", "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}/resume",
              method: :post,
              class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700" %>
      <% end %>
      <% if %w[scheduled sending paused].include?(@campaign.status) %>
        <%= button_to "Cancel", "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}/cancel",
              method: :post,
              data: { turbo_confirm: "Cancel this campaign?" },
              class: "px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700" %>
      <% end %>
    </div>
  </div>

  <dl class="bg-white shadow rounded-lg divide-y divide-gray-200">
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Template</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @campaign.email_template.name %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">List</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @campaign.email_list.name %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Scheduled</dt>
      <dd class="text-sm text-gray-900 col-span-2">
        <% if @campaign.scheduled_at %>
          <%= @campaign.scheduled_at.in_time_zone(@campaign.timezone).to_fs(:long) %> (<%= @campaign.timezone %>)
        <% else %>
          <span class="text-gray-400">not scheduled</span>
        <% end %>
      </dd>
    </div>
    <% if @campaign.recurring? %>
      <div class="px-4 py-3 grid grid-cols-3 gap-4">
        <dt class="text-sm font-medium text-gray-500">Recurrence</dt>
        <dd class="text-sm text-gray-900 col-span-2"><code class="bg-gray-100 px-1 rounded text-xs"><%= @campaign.recurrence_rule %></code></dd>
      </div>
    <% end %>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Started</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @campaign.started_at&.to_fs(:long) || "—" %></dd>
    </div>
    <div class="px-4 py-3 grid grid-cols-3 gap-4">
      <dt class="text-sm font-medium text-gray-500">Completed</dt>
      <dd class="text-sm text-gray-900 col-span-2"><%= @campaign.completed_at&.to_fs(:long) || "—" %></dd>
    </div>
  </dl>

  <div class="grid grid-cols-3 gap-4">
    <div class="bg-white shadow rounded-lg p-4">
      <p class="text-sm font-medium text-gray-500">Sent</p>
      <p class="text-2xl font-semibold text-gray-900 mt-1"><%= @campaign.stats["sent_count"] || 0 %></p>
    </div>
    <div class="bg-white shadow rounded-lg p-4">
      <p class="text-sm font-medium text-gray-500">Delivered</p>
      <p class="text-2xl font-semibold text-gray-900 mt-1"><%= @campaign.stats["delivered_count"] || 0 %></p>
    </div>
    <div class="bg-white shadow rounded-lg p-4">
      <p class="text-sm font-medium text-gray-500">Failed</p>
      <p class="text-2xl font-semibold text-gray-900 mt-1"><%= @campaign.stats["failed_count"] || 0 %></p>
    </div>
  </div>
</div>
```

```erb
<%# app/views/email_campaigns/admin/campaigns/new.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Campaigns", path: "/#{current_customer.id}/email_campaigns/admin/campaigns" },
  { label: "New", path: nil }
]) %>

<div class="max-w-3xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">New Campaign</h1>
  <%= render "form", campaign: @campaign, templates: @templates, lists: @lists,
        url: "/#{current_customer.id}/email_campaigns/admin/campaigns", method: :post %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/campaigns/edit.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Modules", path: nil },
  { label: "Email Campaigns", path: nil },
  { label: "Campaigns", path: "/#{current_customer.id}/email_campaigns/admin/campaigns" },
  { label: @campaign.name, path: "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}" },
  { label: "Edit", path: nil }
]) %>

<div class="max-w-3xl">
  <h1 class="text-2xl font-semibold text-gray-900 mb-6">Edit Campaign</h1>
  <%= render "form", campaign: @campaign, templates: @templates, lists: @lists,
        url: "/#{current_customer.id}/email_campaigns/admin/campaigns/#{@campaign.id}", method: :patch %>
</div>
```

```erb
<%# app/views/email_campaigns/admin/campaigns/_form.html.erb %>
<%= form_with model: campaign, url: url, method: method, local: true, class: "space-y-6" do |f| %>
  <% if campaign.errors.any? %>
    <div class="rounded-md bg-red-50 p-4">
      <ul class="list-disc list-inside text-sm text-red-700">
        <% campaign.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :name, class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_field :name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :email_template_id, "Template", class: "block text-sm font-medium text-gray-700" %>
      <%= f.collection_select :email_template_id, templates, :id, :name, { include_blank: "— select template —" }, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
    <div>
      <%= f.label :email_list_id, "List", class: "block text-sm font-medium text-gray-700" %>
      <%= f.collection_select :email_list_id, lists, :id, :name, { include_blank: "— select list —" }, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :scheduled_at, "Schedule (optional)", class: "block text-sm font-medium text-gray-700" %>
      <%= f.datetime_local_field :scheduled_at, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
    <div>
      <%= f.label :timezone, class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :timezone, ActiveSupport::TimeZone.us_zones.map { |tz| [tz.to_s, tz.tzinfo.name] } + [["UTC", "UTC"]], { include_blank: false }, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
    </div>
  </div>

  <div>
    <%= f.label :recurrence_rule, "Recurrence (RRULE, optional)", class: "block text-sm font-medium text-gray-700" %>
    <%= f.text_field :recurrence_rule, placeholder: "FREQ=DAILY;INTERVAL=1", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 font-mono text-sm" %>
    <p class="mt-1 text-xs text-gray-500">Examples: FREQ=DAILY;INTERVAL=1, FREQ=WEEKLY;INTERVAL=2, FREQ=MONTHLY</p>
  </div>

  <div class="flex justify-end gap-3">
    <%= link_to "Cancel", "/#{current_customer.id}/email_campaigns/admin/campaigns", class: "px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50" %>
    <%= f.submit (campaign.persisted? ? "Update" : "Create"), class: "px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700" %>
  </div>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/email_campaigns/admin/campaigns_controller.rb app/views/email_campaigns/admin/campaigns/
git commit -m "feat(email_campaigns): add admin campaigns CRUD UI with send actions"
```

---

### Task 7: Public Unsubscribe Controller + View

**Files:**
- Create: `app/controllers/email_campaigns/unsubscribes_controller.rb`
- Create: `app/views/email_campaigns/unsubscribes/show.html.erb`

Public endpoint - no auth, no tenant scope. Two-step: GET shows confirmation page, POST processes unsubscribe.

- [ ] **Step 1: Create controller**

```ruby
# app/controllers/email_campaigns/unsubscribes_controller.rb
# frozen_string_literal: true

module EmailCampaigns
  class UnsubscribesController < ApplicationController
    layout "minimal"
    skip_before_action :authenticate_user!, raise: false

    def show
      @subscriber = EmailCampaigns::UnsubscribeHandler.find_by_token(params[:token])
      render :not_found, status: :not_found and return unless @subscriber
    end

    def create
      @subscriber = EmailCampaigns::UnsubscribeHandler.unsubscribe_by_token(params[:token])
      if @subscriber
        @already = @subscriber.unsubscribed_at < 5.seconds.ago
        render :confirmed
      else
        render :not_found, status: :not_found
      end
    end
  end
end
```

NOTE: `layout "minimal"` may not exist - if not, use the existing public layout the project uses (check `app/views/layouts/`). If no minimal layout exists, omit the `layout` line and let Rails use the default.

- [ ] **Step 2: Create views**

```erb
<%# app/views/email_campaigns/unsubscribes/show.html.erb %>
<div class="max-w-md mx-auto mt-16 bg-white p-8 rounded-lg shadow">
  <h1 class="text-2xl font-semibold text-gray-900 mb-2">Unsubscribe</h1>
  <p class="text-gray-700 mb-6">Are you sure you want to unsubscribe <strong><%= @subscriber.email %></strong> from our emails?</p>

  <%= form_with url: "/unsubscribe/#{params[:token]}", method: :post do |f| %>
    <%= f.submit "Yes, unsubscribe me", class: "w-full px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700" %>
  <% end %>
</div>
```

```erb
<%# app/views/email_campaigns/unsubscribes/confirmed.html.erb %>
<div class="max-w-md mx-auto mt-16 bg-white p-8 rounded-lg shadow text-center">
  <h1 class="text-2xl font-semibold text-gray-900 mb-2">Unsubscribed</h1>
  <p class="text-gray-700"><strong><%= @subscriber.email %></strong> has been unsubscribed from our emails.</p>
  <% if @already %>
    <p class="text-xs text-gray-500 mt-3">(You were already unsubscribed.)</p>
  <% end %>
</div>
```

```erb
<%# app/views/email_campaigns/unsubscribes/not_found.html.erb %>
<div class="max-w-md mx-auto mt-16 bg-white p-8 rounded-lg shadow text-center">
  <h1 class="text-2xl font-semibold text-gray-900 mb-2">Link Invalid</h1>
  <p class="text-gray-700">This unsubscribe link is invalid or has expired.</p>
</div>
```

- [ ] **Step 3: Verify routes**

Run: `bin/rails routes | grep unsubscribe`

Expected: `GET /unsubscribe/:token` and `POST /unsubscribe/:token`

- [ ] **Step 4: Commit**

```bash
git add app/controllers/email_campaigns/unsubscribes_controller.rb app/views/email_campaigns/unsubscribes/
git commit -m "feat(email_campaigns): add public unsubscribe page"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run all email-related specs**

Run: `cd /home/ec2-user/anysys && bundle exec rspec spec/models/email_*.rb spec/services/email/ spec/services/email_campaigns/ spec/jobs/email/ spec/jobs/email_campaigns/ spec/requests/email/`

Expected: All tests pass.

- [ ] **Step 2: Verify routes load**

Run: `bin/rails routes | grep -E "email|unsubscribe"`

- [ ] **Step 3: Boot the app and visit pages manually (optional)**

```bash
rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000
```

Visit (with appropriate auth):
- `/:customer_id/email/admin/templates`
- `/:customer_id/email/admin/messages`
- `/:customer_id/email_campaigns/admin/subscribers`
- `/:customer_id/email_campaigns/admin/lists`
- `/:customer_id/email_campaigns/admin/campaigns`

---

## Phase 3 Complete

Admin UI delivered for:
- Email templates (CRUD)
- Email messages (audit log, read-only)
- Subscribers (CRUD)
- Lists (CRUD with JSON segment rules editor)
- Campaigns (CRUD + send/pause/resume/cancel actions)
- Public unsubscribe page

Phase 4 will add rich editors (GrapesJS for templates, Trix for rich text, code editor with syntax highlighting). Phase 5 will integrate with Flowchart steps.
