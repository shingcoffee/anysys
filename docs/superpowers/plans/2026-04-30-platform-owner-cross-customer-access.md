# Platform Owner Cross-Customer Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable platform owners to switch into any customer's context for administrative management with elevated privileges and enhanced audit logging.

**Architecture:** Session-based context switching using `Current` attributes. When a platform owner navigates to another customer's URL, the system detects this, sets `Current.platform_owner_context = true`, and displays a prominent amber banner. All existing `.for_current_customer` calls continue working unchanged.

**Tech Stack:** Ruby on Rails 8.1, ViewComponent, TailwindCSS, StimulusJS, RSpec

**Note:** Enhanced audit logging and platform audit viewer are mentioned in the spec but depend on an Auditable concern that doesn't exist yet. These will be implemented as a follow-up feature when the audit infrastructure is built.

---

## File Structure

### Files to Create

| File | Responsibility |
|------|----------------|
| `spec/models/current_platform_owner_spec.rb` | Tests for platform owner context attributes |
| `spec/controllers/concerns/tenant_context_platform_owner_spec.rb` | Tests for platform owner detection in TenantContext |
| `app/controllers/platform/customer_contexts_controller.rb` | Search, switch, clear actions |
| `spec/controllers/platform/customer_contexts_controller_spec.rb` | Controller tests |
| `app/components/platform/context_banner_component.rb` | Amber banner component |
| `app/components/platform/context_banner_component.html.erb` | Banner template |
| `spec/components/platform/context_banner_component_spec.rb` | Banner tests |
| `app/components/platform/customer_switcher_component.rb` | Customer selector component |
| `app/components/platform/customer_switcher_component.html.erb` | Switcher template |
| `spec/components/platform/customer_switcher_component_spec.rb` | Switcher tests |
| `app/javascript/controllers/platform_customer_switcher_controller.js` | Stimulus controller for switcher |

### Files to Modify

| File | Changes |
|------|---------|
| `app/models/current.rb` | Add `platform_owner_context`, `original_customer`, `acting_as_customer` attributes |
| `app/controllers/concerns/tenant_context.rb` | Add platform owner detection and context setup |
| `app/controllers/application_controller.rb` | Add `platform_elevated_access?` and `require_elevated_access!` helpers |
| `config/routes.rb` | Add platform customer_contexts routes |
| `app/components/dashboard/shell_component.html.erb` | Integrate banner component |
| `app/components/dashboard/topbar_component.rb` | Pass user to template |
| `app/components/dashboard/topbar_component.html.erb` | Integrate customer switcher |
| `app/javascript/controllers/index.js` | Register new Stimulus controller |

---

## Task 1: Current Attributes Extension

**Files:**
- Modify: `app/models/current.rb:26-35`
- Test: `spec/models/current_platform_owner_spec.rb` (create)

- [ ] **Step 1: Write failing tests for platform owner context attributes**

Create `spec/models/current_platform_owner_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Current, 'platform owner context', type: :model do
  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Target Customer') }

  after { Current.reset }

  describe 'platform owner attributes' do
    it 'stores platform_owner_context attribute' do
      Current.platform_owner_context = true
      expect(Current.platform_owner_context).to be true
    end

    it 'stores original_customer attribute' do
      Current.original_customer = platform_customer
      expect(Current.original_customer).to eq(platform_customer)
    end

    it 'stores acting_as_customer attribute' do
      Current.acting_as_customer = target_customer
      expect(Current.acting_as_customer).to eq(target_customer)
    end
  end

  describe '#platform_owner_context?' do
    it 'returns true when platform_owner_context is true' do
      Current.platform_owner_context = true
      expect(Current.platform_owner_context?).to be true
    end

    it 'returns false when platform_owner_context is false' do
      Current.platform_owner_context = false
      expect(Current.platform_owner_context?).to be false
    end

    it 'returns false when platform_owner_context is nil' do
      expect(Current.platform_owner_context?).to be false
    end
  end

  describe '.log_context with platform owner context' do
    before do
      Current.customer = target_customer
      Current.platform_owner_context = true
      Current.original_customer = platform_customer
      Current.acting_as_customer = target_customer
    end

    it 'includes platform owner fields in log context' do
      context = Current.log_context

      expect(context[:platform_owner_context]).to be true
      expect(context[:original_customer_id]).to eq(81_721_200)
      expect(context[:acting_as_customer_id]).to eq(target_customer.id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/current_platform_owner_spec.rb -v`
Expected: FAIL with "undefined method `platform_owner_context='"

- [ ] **Step 3: Add platform owner attributes to Current**

Edit `app/models/current.rb`, add after line 32 (`attribute :ip_address`):

```ruby
  # Platform owner context tracking
  attribute :platform_owner_context
  attribute :original_customer
  attribute :acting_as_customer
```

- [ ] **Step 4: Add platform_owner_context? convenience method**

Edit `app/models/current.rb`, add after the `customer?` method (around line 52):

```ruby
  # Check if currently in platform owner context
  #
  # @return [Boolean] true if acting as another customer
  def platform_owner_context?
    platform_owner_context == true
  end
```

- [ ] **Step 5: Update log_context to include platform owner fields**

Edit `app/models/current.rb`, replace the `log_context` method:

```ruby
  # Returns a hash suitable for structured logging
  #
  # @return [Hash] logging context with tenant information
  def self.log_context
    context = {
      customer_id: customer_id,
      customer_name: customer&.name,
      request_id: request_id,
      ip_address: ip_address
    }

    if platform_owner_context?
      context[:platform_owner_context] = true
      context[:original_customer_id] = original_customer&.id
      context[:acting_as_customer_id] = acting_as_customer&.id
    end

    context.compact
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/current_platform_owner_spec.rb -v`
Expected: All tests pass

- [ ] **Step 7: Run existing Current specs to verify no regression**

Run: `bundle exec rspec spec/models/current_spec.rb -v`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add app/models/current.rb spec/models/current_platform_owner_spec.rb
git commit -m "feat: add platform owner context attributes to Current"
```

---

## Task 2: TenantContext Platform Owner Detection

**Files:**
- Modify: `app/controllers/concerns/tenant_context.rb:139-146`
- Test: `spec/controllers/concerns/tenant_context_platform_owner_spec.rb` (create)

- [ ] **Step 1: Write failing tests for platform owner detection**

Create `spec/controllers/concerns/tenant_context_platform_owner_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantContext, 'platform owner context', type: :controller do
  controller(ApplicationController) do
    set_tenant_from_route_params

    def index
      render json: {
        customer_id: Current.customer_id,
        platform_owner_context: Current.platform_owner_context?,
        original_customer_id: Current.original_customer&.id,
        acting_as_customer_id: Current.acting_as_customer&.id
      }
    end
  end

  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Target Customer') }
  let(:regular_customer) { create(:customer, name: 'Regular Customer') }

  let(:platform_owner_user) do
    create(:user, customer: platform_customer, role: :owner, email: 'platform@test.io')
  end

  let(:regular_owner_user) do
    create(:user, customer: regular_customer, role: :owner, email: 'regular@test.io')
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  after { Current.reset }

  describe 'platform owner accessing another customer' do
    before { sign_in platform_owner_user }

    it 'sets platform_owner_context to true' do
      get :index, params: { customer_id: target_customer.id }

      json = JSON.parse(response.body)
      expect(json['platform_owner_context']).to be true
    end

    it 'sets Current.customer to target customer' do
      get :index, params: { customer_id: target_customer.id }

      json = JSON.parse(response.body)
      expect(json['customer_id']).to eq(target_customer.id)
    end

    it 'sets original_customer to platform customer' do
      get :index, params: { customer_id: target_customer.id }

      json = JSON.parse(response.body)
      expect(json['original_customer_id']).to eq(81_721_200)
    end

    it 'sets acting_as_customer to target customer' do
      get :index, params: { customer_id: target_customer.id }

      json = JSON.parse(response.body)
      expect(json['acting_as_customer_id']).to eq(target_customer.id)
    end
  end

  describe 'platform owner accessing own customer' do
    before { sign_in platform_owner_user }

    it 'does not set platform_owner_context' do
      get :index, params: { customer_id: platform_customer.id }

      json = JSON.parse(response.body)
      expect(json['platform_owner_context']).to be false
    end
  end

  describe 'regular user accessing own customer' do
    before { sign_in regular_owner_user }

    it 'does not set platform_owner_context' do
      get :index, params: { customer_id: regular_customer.id }

      json = JSON.parse(response.body)
      expect(json['platform_owner_context']).to be false
    end
  end

  describe 'regular user attempting to access another customer' do
    before { sign_in regular_owner_user }

    it 'does not set platform_owner_context' do
      get :index, params: { customer_id: target_customer.id }

      json = JSON.parse(response.body)
      expect(json['platform_owner_context']).to be false
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/controllers/concerns/tenant_context_platform_owner_spec.rb -v`
Expected: FAIL (platform_owner_context returns false/nil)

- [ ] **Step 3: Add platform owner detection methods to TenantContext**

Edit `app/controllers/concerns/tenant_context.rb`, add before the `private` keyword (around line 109):

```ruby
  # ==========================================================================
  # Platform Owner Context
  # ==========================================================================

  # Clear platform owner context (return to own customer)
  def clear_platform_owner_context
    session.delete(:platform_acting_as_customer_id)
    Current.platform_owner_context = false
    Current.original_customer = nil
    Current.acting_as_customer = nil
  end
```

- [ ] **Step 4: Add private helper methods for platform owner detection**

Edit `app/controllers/concerns/tenant_context.rb`, add in the private section (after `set_request_metadata` method):

```ruby
  # ==========================================================================
  # Platform Owner Detection
  # ==========================================================================

  # Check if current user is a platform owner accessing another customer
  #
  # @param target_customer [Customer] the customer being accessed
  # @return [Boolean] true if platform owner accessing different customer
  def platform_owner_acting_as_other_customer?(target_customer)
    return false unless respond_to?(:current_user) && current_user&.platform_owner?
    return false unless target_customer.present?

    target_customer.id != current_user.customer_id
  end

  # Set up platform owner context attributes
  #
  # @param target_customer [Customer] the customer being administered
  def setup_platform_owner_context(target_customer)
    Current.customer = target_customer
    Current.platform_owner_context = true
    Current.original_customer = current_user.customer
    Current.acting_as_customer = target_customer

    session[:platform_acting_as_customer_id] = target_customer.id
  end
```

- [ ] **Step 5: Modify set_current_tenant to detect platform owner context**

Edit `app/controllers/concerns/tenant_context.rb`, replace the `set_current_tenant` method:

```ruby
  # Set the current tenant from customer_id
  #
  # @param customer_id [String, Integer] the customer ID
  # @param required [Boolean] whether tenant is required
  def set_current_tenant(customer_id, required)
    return unless customer_id.present?

    customer = Customer.find_by(id: customer_id)

    if platform_owner_acting_as_other_customer?(customer)
      setup_platform_owner_context(customer)
    else
      Current.customer = customer
      Current.platform_owner_context = false
    end

    render_tenant_not_found_error(customer_id) if required && Current.customer.nil?
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/controllers/concerns/tenant_context_platform_owner_spec.rb -v`
Expected: All tests pass

- [ ] **Step 7: Run existing TenantContext specs to verify no regression**

Run: `bundle exec rspec spec/controllers/concerns/ -v`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add app/controllers/concerns/tenant_context.rb spec/controllers/concerns/tenant_context_platform_owner_spec.rb
git commit -m "feat: add platform owner detection to TenantContext"
```

---

## Task 3: ApplicationController Authorization Helpers

**Files:**
- Modify: `app/controllers/application_controller.rb:69-75`
- Test: `spec/controllers/application_controller_spec.rb` (modify)

- [ ] **Step 1: Write failing tests for elevated access helpers**

Add to `spec/controllers/application_controller_spec.rb`:

```ruby
RSpec.describe ApplicationController, 'platform elevated access', type: :controller do
  controller do
    def index
      render json: { elevated: platform_elevated_access? }
    end

    def elevated_action
      require_elevated_access!
      render json: { success: true }
    end
  end

  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Target Customer') }
  let(:regular_customer) { create(:customer, name: 'Regular Customer') }

  let(:platform_owner_user) do
    create(:user, customer: platform_customer, role: :owner, email: 'platform@test.io')
  end

  let(:regular_owner_user) do
    create(:user, customer: regular_customer, role: :owner, email: 'regular@test.io')
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'elevated_action' => 'anonymous#elevated_action'
    end
  end

  after { Current.reset }

  describe '#platform_elevated_access?' do
    context 'platform owner in platform owner context' do
      before do
        sign_in platform_owner_user
        Current.platform_owner_context = true
      end

      it 'returns true' do
        get :index, params: { customer_id: target_customer.id }
        json = JSON.parse(response.body)
        expect(json['elevated']).to be true
      end
    end

    context 'platform owner in own context' do
      before do
        sign_in platform_owner_user
        Current.platform_owner_context = false
      end

      it 'returns false' do
        get :index, params: { customer_id: platform_customer.id }
        json = JSON.parse(response.body)
        expect(json['elevated']).to be false
      end
    end

    context 'regular user' do
      before do
        sign_in regular_owner_user
        Current.platform_owner_context = false
      end

      it 'returns false' do
        get :index, params: { customer_id: regular_customer.id }
        json = JSON.parse(response.body)
        expect(json['elevated']).to be false
      end
    end
  end

  describe '#require_elevated_access!' do
    context 'with elevated access' do
      before do
        sign_in platform_owner_user
        Current.platform_owner_context = true
      end

      it 'allows the action' do
        get :elevated_action, params: { customer_id: target_customer.id }
        expect(response).to have_http_status(:ok)
      end
    end

    context 'without elevated access' do
      before do
        sign_in regular_owner_user
        Current.platform_owner_context = false
      end

      it 'returns forbidden for JSON request' do
        get :elevated_action, params: { customer_id: regular_customer.id }, format: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/controllers/application_controller_spec.rb -v --example "platform elevated access"`
Expected: FAIL with "undefined method `platform_elevated_access?'"

- [ ] **Step 3: Add platform_elevated_access? helper**

Edit `app/controllers/application_controller.rb`, add after `require_platform_owner!` method (around line 75):

```ruby
  # Check if current user has platform elevated access
  # This is true when a platform owner is acting in another customer's context
  #
  # @return [Boolean] true if elevated access is available
  def platform_elevated_access?
    Current.platform_owner_context? && current_user&.platform_owner?
  end

  # Require platform elevated access for an action
  # Use for operations that only platform owners can perform in another customer's context
  def require_elevated_access!
    return if platform_elevated_access?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "This action requires platform owner privileges." }
      format.json { render json: { error: "elevated_access_required" }, status: :forbidden }
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/controllers/application_controller_spec.rb -v --example "platform elevated access"`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app/controllers/application_controller.rb spec/controllers/application_controller_spec.rb
git commit -m "feat: add platform elevated access helpers to ApplicationController"
```

---

## Task 4: Platform Customer Contexts Controller

**Files:**
- Create: `app/controllers/platform/customer_contexts_controller.rb`
- Create: `spec/controllers/platform/customer_contexts_controller_spec.rb`

- [ ] **Step 1: Write failing controller tests**

Create `spec/controllers/platform/customer_contexts_controller_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Platform::CustomerContextsController, type: :controller do
  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Target Customer') }
  let(:other_customer) { create(:customer, name: 'Other Customer') }

  let(:platform_owner_user) do
    create(:user, customer: platform_customer, role: :owner, email: 'platform@test.io')
  end

  let(:regular_user) do
    create(:user, customer: other_customer, role: :owner, email: 'regular@test.io')
  end

  after { Current.reset }

  describe 'GET #search' do
    context 'as platform owner' do
      before { sign_in platform_owner_user }

      it 'returns matching customers as JSON' do
        create(:customer, name: 'Acme Corp')
        create(:customer, name: 'Acme Industries')
        create(:customer, name: 'Other Company')

        get :search, params: { q: 'Acme' }, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.length).to eq(2)
        expect(json.map { |c| c['name'] }).to all(include('Acme'))
      end

      it 'limits results to 20' do
        25.times { |i| create(:customer, name: "Test Customer #{i}") }

        get :search, params: { q: 'Test' }, format: :json

        json = JSON.parse(response.body)
        expect(json.length).to eq(20)
      end

      it 'returns empty array for no matches' do
        get :search, params: { q: 'NonExistent' }, format: :json

        json = JSON.parse(response.body)
        expect(json).to eq([])
      end
    end

    context 'as regular user' do
      before { sign_in regular_user }

      it 'returns forbidden' do
        get :search, params: { q: 'test' }, format: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'as unauthenticated user' do
      it 'redirects to login' do
        get :search, params: { q: 'test' }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST #switch' do
    context 'as platform owner' do
      before { sign_in platform_owner_user }

      it 'sets session and redirects to customer dashboard' do
        post :switch, params: { customer_id: target_customer.id }

        expect(session[:platform_acting_as_customer_id]).to eq(target_customer.id)
        expect(response).to redirect_to("/#{target_customer.id}/")
      end

      it 'sets flash notice with customer name' do
        post :switch, params: { customer_id: target_customer.id }

        expect(flash[:notice]).to include(target_customer.name)
      end

      it 'returns not found for invalid customer' do
        post :switch, params: { customer_id: 99999999 }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'as regular user' do
      before { sign_in regular_user }

      it 'returns forbidden' do
        post :switch, params: { customer_id: target_customer.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #clear' do
    context 'as platform owner' do
      before do
        sign_in platform_owner_user
        session[:platform_acting_as_customer_id] = target_customer.id
      end

      it 'clears session and redirects to platform customer' do
        delete :clear

        expect(session[:platform_acting_as_customer_id]).to be_nil
        expect(response).to redirect_to("/#{platform_customer.id}/")
      end

      it 'sets flash notice' do
        delete :clear

        expect(flash[:notice]).to include('Returned')
      end
    end

    context 'as regular user' do
      before { sign_in regular_user }

      it 'returns forbidden' do
        delete :clear
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/controllers/platform/customer_contexts_controller_spec.rb -v`
Expected: FAIL with "uninitialized constant Platform::CustomerContextsController"

- [ ] **Step 3: Create the controller**

Create `app/controllers/platform/customer_contexts_controller.rb`:

```ruby
# frozen_string_literal: true

module Platform
  class CustomerContextsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_platform_owner!
    before_action :set_customer, only: [:switch]

    def search
      customers = Customer.search_by_name(params[:q]).limit(20)
      render json: customers.map { |c|
        { id: c.id, name: c.name, industry: c.industry&.titleize }
      }
    end

    def switch
      session[:platform_acting_as_customer_id] = @customer.id
      redirect_to "/#{@customer.id}/", notice: "Now acting as #{@customer.name}"
    end

    def clear
      clear_platform_owner_context
      redirect_to "/#{current_user.customer_id}/", notice: "Returned to platform context"
    end

    private

    def set_customer
      @customer = Customer.find_by(id: params[:customer_id])
      render_not_found unless @customer
    end

    def render_not_found
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Customer not found" }
        format.json { render json: { error: "not_found" }, status: :not_found }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/controllers/platform/customer_contexts_controller_spec.rb -v`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app/controllers/platform/customer_contexts_controller.rb spec/controllers/platform/customer_contexts_controller_spec.rb
git commit -m "feat: add Platform::CustomerContextsController for context switching"
```

---

## Task 5: Routes for Customer Contexts

**Files:**
- Modify: `config/routes.rb:250-255`

- [ ] **Step 1: Add routes for customer contexts**

Edit `config/routes.rb`, add inside the `namespace :platform` block (after line 254):

```ruby
    resources :customer_contexts, only: [] do
      collection do
        get :search
        post :switch
        delete :clear
      end
    end
```

- [ ] **Step 2: Verify routes exist**

Run: `bundle exec rails routes | grep customer_contexts`
Expected output:
```
search_platform_customer_contexts GET    /platform/customer_contexts/search(.:format)  platform/customer_contexts#search
switch_platform_customer_contexts POST   /platform/customer_contexts/switch(.:format)  platform/customer_contexts#switch
clear_platform_customer_contexts  DELETE /platform/customer_contexts/clear(.:format)   platform/customer_contexts#clear
```

- [ ] **Step 3: Run controller tests again to verify routing works**

Run: `bundle exec rspec spec/controllers/platform/customer_contexts_controller_spec.rb -v`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add routes for platform customer context switching"
```

---

## Task 6: Context Banner Component

**Files:**
- Create: `app/components/platform/context_banner_component.rb`
- Create: `app/components/platform/context_banner_component.html.erb`
- Create: `spec/components/platform/context_banner_component_spec.rb`

- [ ] **Step 1: Write failing component tests**

Create `spec/components/platform/context_banner_component_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Platform::ContextBannerComponent, type: :component do
  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Acme Industries') }

  after { Current.reset }

  describe '#render?' do
    it 'returns true when platform_owner_context is true' do
      Current.platform_owner_context = true
      Current.acting_as_customer = target_customer

      component = described_class.new
      expect(component.render?).to be true
    end

    it 'returns false when platform_owner_context is false' do
      Current.platform_owner_context = false

      component = described_class.new
      expect(component.render?).to be false
    end

    it 'returns false when platform_owner_context is nil' do
      component = described_class.new
      expect(component.render?).to be false
    end
  end

  context 'when rendered' do
    before do
      Current.platform_owner_context = true
      Current.acting_as_customer = target_customer
      Current.original_customer = platform_customer
    end

    it 'displays platform admin mode text' do
      render_inline(described_class.new)

      expect(page).to have_text('Platform Admin Mode')
    end

    it 'displays target customer name' do
      render_inline(described_class.new)

      expect(page).to have_text('Acme Industries')
    end

    it 'displays target customer ID' do
      render_inline(described_class.new)

      expect(page).to have_text(target_customer.id.to_s)
    end

    it 'has return to platform link' do
      render_inline(described_class.new)

      expect(page).to have_link('Return to Platform', href: clear_platform_customer_contexts_path)
    end

    it 'uses amber background color' do
      render_inline(described_class.new)

      expect(page).to have_css('.bg-amber-500')
    end

    it 'is sticky at top' do
      render_inline(described_class.new)

      expect(page).to have_css('.sticky.top-0')
    end
  end

  context 'when not in platform owner context' do
    before do
      Current.platform_owner_context = false
    end

    it 'does not render anything' do
      render_inline(described_class.new)

      expect(page.native.inner_html).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/components/platform/context_banner_component_spec.rb -v`
Expected: FAIL with "uninitialized constant Platform::ContextBannerComponent"

- [ ] **Step 3: Create the component Ruby file**

Create `app/components/platform/context_banner_component.rb`:

```ruby
# frozen_string_literal: true

module Platform
  class ContextBannerComponent < ApplicationComponent
    def render?
      Current.platform_owner_context?
    end

    def customer_name
      Current.acting_as_customer&.name
    end

    def customer_id
      Current.acting_as_customer&.id
    end
  end
end
```

- [ ] **Step 4: Create the component template**

Create `app/components/platform/context_banner_component.html.erb`:

```erb
<div class="bg-amber-500 text-amber-950 px-4 py-2 flex items-center justify-between sticky top-0 z-50">
  <div class="flex items-center gap-2">
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
    </svg>
    <span class="font-semibold">Platform Admin Mode</span>
    <span class="hidden sm:inline">&mdash;</span>
    <span>Acting as <strong><%= customer_name %></strong> <span class="text-amber-800">(ID: <%= customer_id %>)</span></span>
  </div>

  <%= link_to "Return to Platform",
      clear_platform_customer_contexts_path,
      data: { turbo_method: :delete },
      class: "bg-amber-700 hover:bg-amber-800 text-white px-3 py-1 rounded text-sm font-medium transition-colors" %>
</div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/platform/context_banner_component_spec.rb -v`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/components/platform/context_banner_component.rb app/components/platform/context_banner_component.html.erb spec/components/platform/context_banner_component_spec.rb
git commit -m "feat: add Platform::ContextBannerComponent for visual indicator"
```

---

## Task 7: Customer Switcher Component

**Files:**
- Create: `app/components/platform/customer_switcher_component.rb`
- Create: `app/components/platform/customer_switcher_component.html.erb`
- Create: `spec/components/platform/customer_switcher_component_spec.rb`

- [ ] **Step 1: Write failing component tests**

Create `spec/components/platform/customer_switcher_component_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Platform::CustomerSwitcherComponent, type: :component do
  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:regular_customer) { create(:customer, name: 'Regular Customer') }

  let(:platform_owner_user) do
    create(:user, customer: platform_customer, role: :owner, email: 'platform@test.io')
  end

  let(:regular_user) do
    create(:user, customer: regular_customer, role: :member, email: 'regular@test.io')
  end

  describe '#render?' do
    it 'returns true for platform owner user' do
      component = described_class.new(user: platform_owner_user)
      expect(component.render?).to be true
    end

    it 'returns false for regular user' do
      component = described_class.new(user: regular_user)
      expect(component.render?).to be false
    end

    it 'returns false for nil user' do
      component = described_class.new(user: nil)
      expect(component.render?).to be false
    end
  end

  context 'when rendered for platform owner' do
    it 'displays switch customer button' do
      render_inline(described_class.new(user: platform_owner_user))

      expect(page).to have_css('button[aria-label="Switch Customer"]')
    end

    it 'has stimulus controller' do
      render_inline(described_class.new(user: platform_owner_user))

      expect(page).to have_css('[data-controller="platform-customer-switcher"]')
    end

    it 'has search input' do
      render_inline(described_class.new(user: platform_owner_user))

      expect(page).to have_css('input[placeholder*="Search customers"]')
    end

    it 'has search endpoint configured' do
      render_inline(described_class.new(user: platform_owner_user))

      expect(page).to have_css("[data-platform-customer-switcher-search-url-value=\"#{search_platform_customer_contexts_path}\"]")
    end
  end

  context 'when not rendered for regular user' do
    it 'does not render anything' do
      render_inline(described_class.new(user: regular_user))

      expect(page.native.inner_html).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/components/platform/customer_switcher_component_spec.rb -v`
Expected: FAIL with "uninitialized constant Platform::CustomerSwitcherComponent"

- [ ] **Step 3: Create the component Ruby file**

Create `app/components/platform/customer_switcher_component.rb`:

```ruby
# frozen_string_literal: true

module Platform
  class CustomerSwitcherComponent < ApplicationComponent
    def initialize(user:)
      @user = user
    end

    attr_reader :user

    def render?
      user&.platform_owner?
    end
  end
end
```

- [ ] **Step 4: Create the component template**

Create `app/components/platform/customer_switcher_component.html.erb`:

```erb
<div data-controller="platform-customer-switcher"
     data-platform-customer-switcher-search-url-value="<%= search_platform_customer_contexts_path %>"
     data-platform-customer-switcher-switch-url-value="<%= switch_platform_customer_contexts_path %>"
     class="relative">
  <%# Trigger Button %>
  <button type="button"
          data-action="click->platform-customer-switcher#toggle"
          aria-label="Switch Customer"
          class="h-9 w-9 inline-flex items-center justify-center text-gray-500 rounded-lg hover:bg-gray-100 active:bg-gray-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 transition-colors">
    <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 003.741-.479 3 3 0 00-4.682-2.72m.94 3.198l.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0112 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 016 18.719m12 0a5.971 5.971 0 00-.941-3.197m0 0A5.995 5.995 0 0012 12.75a5.995 5.995 0 00-5.058 2.772m0 0a3 3 0 00-4.681 2.72 8.986 8.986 0 003.74.477m.94-3.197a5.971 5.971 0 00-.94 3.197M15 6.75a3 3 0 11-6 0 3 3 0 016 0zm6 3a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0zm-13.5 0a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z"/>
    </svg>
  </button>

  <%# Dropdown Panel %>
  <div data-platform-customer-switcher-target="panel"
       class="hidden absolute right-0 top-full mt-2 w-80 bg-white rounded-lg shadow-lg border border-gray-200 z-50">
    <div class="p-3 border-b border-gray-100">
      <div class="text-xs font-medium text-gray-500 uppercase tracking-wide mb-2">Switch Customer</div>
      <input type="text"
             data-platform-customer-switcher-target="search"
             data-action="input->platform-customer-switcher#search"
             placeholder="Search customers by name..."
             class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent">
    </div>

    <div data-platform-customer-switcher-target="results"
         class="max-h-64 overflow-y-auto">
      <div class="p-4 text-sm text-gray-500 text-center">
        Type to search customers...
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/components/platform/customer_switcher_component_spec.rb -v`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add app/components/platform/customer_switcher_component.rb app/components/platform/customer_switcher_component.html.erb spec/components/platform/customer_switcher_component_spec.rb
git commit -m "feat: add Platform::CustomerSwitcherComponent for customer selection"
```

---

## Task 8: Stimulus Controller for Customer Switcher

**Files:**
- Create: `app/javascript/controllers/platform_customer_switcher_controller.js`
- Modify: `app/javascript/controllers/index.js`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/platform_customer_switcher_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "search", "results"]
  static values = {
    searchUrl: String,
    switchUrl: String
  }

  connect() {
    this.searchTimeout = null
    document.addEventListener("click", this.handleOutsideClick.bind(this))
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick.bind(this))
  }

  toggle() {
    this.panelTarget.classList.toggle("hidden")
    if (!this.panelTarget.classList.contains("hidden")) {
      this.searchTarget.focus()
    }
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  search() {
    clearTimeout(this.searchTimeout)
    const query = this.searchTarget.value.trim()

    if (query.length < 2) {
      this.resultsTarget.innerHTML = `
        <div class="p-4 text-sm text-gray-500 text-center">
          Type at least 2 characters to search...
        </div>
      `
      return
    }

    this.searchTimeout = setTimeout(() => {
      this.performSearch(query)
    }, 300)
  }

  async performSearch(query) {
    this.resultsTarget.innerHTML = `
      <div class="p-4 text-sm text-gray-500 text-center">
        Searching...
      </div>
    `

    try {
      const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(query)}`, {
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) throw new Error("Search failed")

      const customers = await response.json()
      this.renderResults(customers)
    } catch (error) {
      this.resultsTarget.innerHTML = `
        <div class="p-4 text-sm text-red-500 text-center">
          Search failed. Please try again.
        </div>
      `
    }
  }

  renderResults(customers) {
    if (customers.length === 0) {
      this.resultsTarget.innerHTML = `
        <div class="p-4 text-sm text-gray-500 text-center">
          No customers found
        </div>
      `
      return
    }

    const html = customers.map(customer => `
      <button type="button"
              data-action="click->platform-customer-switcher#selectCustomer"
              data-customer-id="${customer.id}"
              class="w-full px-4 py-3 text-left hover:bg-gray-50 focus:bg-gray-50 focus:outline-none border-b border-gray-100 last:border-0">
        <div class="text-sm font-medium text-gray-900">${this.escapeHtml(customer.name)}</div>
        <div class="text-xs text-gray-500">ID: ${customer.id}${customer.industry ? ` • ${customer.industry}` : ''}</div>
      </button>
    `).join('')

    this.resultsTarget.innerHTML = html
  }

  selectCustomer(event) {
    const customerId = event.currentTarget.dataset.customerId
    this.switchToCustomer(customerId)
  }

  async switchToCustomer(customerId) {
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.switchUrlValue

    const csrfToken = document.querySelector('meta[name="csrf-token"]').content
    const csrfInput = document.createElement("input")
    csrfInput.type = "hidden"
    csrfInput.name = "authenticity_token"
    csrfInput.value = csrfToken

    const customerInput = document.createElement("input")
    customerInput.type = "hidden"
    customerInput.name = "customer_id"
    customerInput.value = customerId

    form.appendChild(csrfInput)
    form.appendChild(customerInput)
    document.body.appendChild(form)
    form.submit()
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
```

- [ ] **Step 2: Register the controller in index.js**

Edit `app/javascript/controllers/index.js`, add the import and registration:

```javascript
import PlatformCustomerSwitcherController from "./platform_customer_switcher_controller"
application.register("platform-customer-switcher", PlatformCustomerSwitcherController)
```

- [ ] **Step 3: Verify JavaScript builds without errors**

Run: `bundle exec rails assets:precompile` (or check dev server)
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/platform_customer_switcher_controller.js app/javascript/controllers/index.js
git commit -m "feat: add Stimulus controller for customer switcher"
```

---

## Task 9: Integrate Components into Layout

**Files:**
- Modify: `app/components/dashboard/shell_component.html.erb`
- Modify: `app/components/dashboard/topbar_component.rb`
- Modify: `app/components/dashboard/topbar_component.html.erb`

- [ ] **Step 1: Add banner to shell component**

Edit `app/components/dashboard/shell_component.html.erb`, add at the very beginning (line 1):

```erb
<%= render Platform::ContextBannerComponent.new %>
```

The file should now start with:
```erb
<%= render Platform::ContextBannerComponent.new %>
<div class="min-h-screen flex flex-col bg-[#f8f9fb]">
  ...
```

- [ ] **Step 2: Update topbar component to accept user**

The TopbarComponent already accepts `user:` parameter. Verify `app/components/dashboard/topbar_component.rb` has:

```ruby
def initialize(customer:, user:)
  @customer = customer
  @user = user
end

attr_reader :customer, :user
```

- [ ] **Step 3: Add customer switcher to topbar**

Edit `app/components/dashboard/topbar_component.html.erb`, add the customer switcher in the actions area (after the search, before help menu):

Find this line (around line 33):
```erb
    <%# Actions %>
    <div class="flex items-center gap-1 sm:gap-2 justify-end">
```

After the mobile search div (around line 35), add:
```erb
      <%= render Platform::CustomerSwitcherComponent.new(user: user) %>
```

So it becomes:
```erb
    <%# Actions %>
    <div class="flex items-center gap-1 sm:gap-2 justify-end">
      <div class="md:hidden">
        <%= render Dashboard::InlineSearchComponent.new(customer_id: customer.id, mobile: true) %>
      </div>
      <%= render Platform::CustomerSwitcherComponent.new(user: user) %>
      <%= render Dashboard::HelpMenuComponent.new %>
      <%= render Dashboard::NotificationsButtonComponent.new %>
      <%= render Dashboard::UserMenuComponent.new(user: user, customer: customer) if user %>
    </div>
```

- [ ] **Step 4: Run component tests to verify integration**

Run: `bundle exec rspec spec/components/dashboard/topbar_component_spec.rb -v`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app/components/dashboard/shell_component.html.erb app/components/dashboard/topbar_component.html.erb
git commit -m "feat: integrate platform owner components into dashboard layout"
```

---

## Task 10: Integration Test

**Files:**
- Create: `spec/features/platform_owner_context_switch_spec.rb`

- [ ] **Step 1: Write integration test**

Create `spec/features/platform_owner_context_switch_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Platform Owner Context Switching', type: :feature, js: true do
  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Acme Industries') }

  let(:platform_owner_user) do
    create(:user, customer: platform_customer, role: :owner, email: 'platform@test.io', password: 'password123')
  end

  before do
    platform_customer
    target_customer
  end

  describe 'context switching flow' do
    it 'allows platform owner to switch to another customer context' do
      sign_in platform_owner_user
      visit "/#{platform_customer.id}/"

      # Should see customer switcher button
      expect(page).to have_css('button[aria-label="Switch Customer"]')

      # Click switcher and search
      find('button[aria-label="Switch Customer"]').click
      fill_in 'Search customers by name...', with: 'Acme'

      # Should see search result
      expect(page).to have_text('Acme Industries')

      # Click to switch
      click_button 'Acme Industries'

      # Should redirect and show banner
      expect(page).to have_current_path("/#{target_customer.id}/")
      expect(page).to have_text('Platform Admin Mode')
      expect(page).to have_text('Acme Industries')
      expect(page).to have_link('Return to Platform')
    end

    it 'allows platform owner to return to own context' do
      sign_in platform_owner_user
      visit "/#{target_customer.id}/"

      # Should show banner since accessing different customer
      expect(page).to have_text('Platform Admin Mode')

      # Click return link
      click_link 'Return to Platform'

      # Should redirect to platform owner's customer
      expect(page).to have_current_path("/#{platform_customer.id}/")
      expect(page).not_to have_text('Platform Admin Mode')
    end
  end

  describe 'banner visibility' do
    it 'shows banner when platform owner is in another customer context' do
      sign_in platform_owner_user
      visit "/#{target_customer.id}/"

      expect(page).to have_css('.bg-amber-500')
      expect(page).to have_text('Platform Admin Mode')
    end

    it 'does not show banner when platform owner is in own context' do
      sign_in platform_owner_user
      visit "/#{platform_customer.id}/"

      expect(page).not_to have_css('.bg-amber-500')
      expect(page).not_to have_text('Platform Admin Mode')
    end
  end
end
```

- [ ] **Step 2: Run integration tests**

Run: `bundle exec rspec spec/features/platform_owner_context_switch_spec.rb -v`
Expected: All tests pass (may require system test setup with Capybara/Selenium)

- [ ] **Step 3: Commit**

```bash
git add spec/features/platform_owner_context_switch_spec.rb
git commit -m "test: add integration tests for platform owner context switching"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Run all platform owner related tests**

Run: `bundle exec rspec spec/models/current_platform_owner_spec.rb spec/controllers/concerns/tenant_context_platform_owner_spec.rb spec/controllers/platform/ spec/components/platform/ -v`
Expected: All tests pass

- [ ] **Step 2: Run full test suite to check for regressions**

Run: `bundle exec rspec`
Expected: No new failures

- [ ] **Step 3: Manual verification in browser**

1. Log in as platform owner (customer 81721200, owner role)
2. Verify customer switcher button appears in topbar
3. Search for a customer and switch
4. Verify amber banner appears
5. Verify normal CRUD operations work in target customer context
6. Click "Return to Platform" and verify return to own context

- [ ] **Step 4: Final commit with summary**

```bash
git add -A
git commit -m "feat: complete platform owner cross-customer access implementation

- Added platform owner context attributes to Current
- Added platform owner detection in TenantContext
- Added CustomerContextsController for search/switch/clear
- Added ContextBannerComponent (amber sticky banner)
- Added CustomerSwitcherComponent (dropdown with search)
- Integrated components into dashboard layout
- Full test coverage with unit and integration tests"
```
