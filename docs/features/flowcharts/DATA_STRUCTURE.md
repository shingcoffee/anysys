# Flowcharts Data Structure

## Database Schema

```
Table: flowcharts
┌──────────────────┬──────────────┬──────────┬────────────┬─────────┐
│ Column           │ Type         │ Null     │ Default    │ Index   │
├──────────────────┼──────────────┼──────────┼────────────┼─────────┤
│ id               │ INTEGER      │ NOT NULL │            │ PRIMARY │
│ uuid             │ VARCHAR      │ NOT NULL │            │ UNIQUE  │
│ name             │ VARCHAR      │ NOT NULL │            │ YES     │
│ description      │ TEXT         │ NULL     │            │         │
│ flowchart_type   │ INTEGER      │ NOT NULL │ 0          │ YES     │
│ status           │ INTEGER      │ NOT NULL │ 0          │ YES     │
│ configuration    │ TEXT (JSON)  │ NOT NULL │            │         │
│ activity         │ TEXT         │ NULL     │            │         │
│ entity_id        │ INTEGER      │ NULL     │            │ YES     │
│ customer_id      │ INTEGER      │ NULL     │            │ YES     │
│ created_at       │ DATETIME(6)  │ NOT NULL │            │ YES     │
│ updated_at       │ DATETIME(6)  │ NOT NULL │            │         │
└──────────────────┴──────────────┴──────────┴────────────┴─────────┘
```

## Field Details

### 1. `id` (INTEGER, PRIMARY KEY)
- Auto-incrementing unique identifier
- Example: `1`, `29`, `42`

### 2. `uuid` (VARCHAR, NOT NULL, UNIQUE)
- Universally unique identifier for the flowchart
- Used in URLs for accessing flowcharts
- Format: UUID v4 (e.g., `8151cd9c-b071-431d-b250-0e6e56bf63dd`)
- Auto-generated on create

### 3. `name` (VARCHAR, NOT NULL, INDEXED)
- Human-readable name of the flowchart
- Max length: 100 characters
- Must be unique within a customer (for custom flowcharts)
- Must be globally unique (for blueprint flowcharts)
- Examples: `"Student Enrollment"`, `"Create Entity Entry"`, `"Order Processing"`

### 4. `description` (TEXT, NULL)
- Optional detailed description of the flowchart
- Examples: `"Process for enrolling new students"`, `"Blueprint to create a new entry for entity"`

### 5. `flowchart_type` (INTEGER, NOT NULL, INDEXED)
- Type of flowchart - determines scope and entity binding
- **Enum values:**
  - `0` = `"custom"` - Customer-specific, bound to an entity
  - `1` = `"blueprint"` - Shared template, no entity binding
- Default: `0` (custom)

### 6. `status` (INTEGER, NOT NULL, INDEXED)
- Soft delete status of the flowchart
- **Enum values:**
  - `0` = `"active"` - Normal, visible flowchart
  - `1` = `"deleted"` - Soft-deleted, hidden from default queries
- Default: `0` (active)

### 7. `configuration` (TEXT, NOT NULL)
- JSON string containing the complete flowchart structure
- Contains: elements, connections, metadata
- **Must be valid JSON**
- **Required structure:**
  ```json
  {
    "elements": [...],
    "connections": [...],
    "metadata": {...}
  }
  ```

### 8. `activity` (TEXT, NULL)
- Auto-generated Ruby code (Trailblazer Activity)
- Generated from configuration before save
- Can be executed to run the flowchart logic
- Example:
  ```ruby
  class CreateEntityEntryActivity < Trailblazer::Activity::Railway
    step :new_model
    step :build_contract
    step :validate_contract
    step :save_model
  end
  ```

### 9. `entity_id` (INTEGER, NULL, INDEXED)
- Foreign key to `entities` table
- **Required** for custom flowcharts (type = 0)
- **Must be NULL** for blueprint flowcharts (type = 1)
- Links flowchart to a specific entity model

### 10. `customer_id` (INTEGER, NULL, INDEXED)
- Foreign key to `customers` table
- **Required** for custom flowcharts (type = 0)
- **Must be NULL** for blueprint flowcharts (type = 1)
- Provides tenant isolation for custom flowcharts

### 11. `created_at` (DATETIME(6), NOT NULL, INDEXED)
- Timestamp when flowchart was created
- Auto-set by Rails

### 12. `updated_at` (DATETIME(6), NOT NULL)
- Timestamp when flowchart was last updated
- Auto-updated by Rails

## Configuration JSON Structure

### Complete Configuration Example
```json
{
  "elements": [
    {
      "id": "el_0de60a01",
      "type": "start",
      "x": 400,
      "y": 100,
      "width": 100,
      "height": 45,
      "label": "Start",
      "properties": {
        "inputs": [{"value": "all params"}],
        "outputs": [{"value": "ctx"}],
        "description": ""
      }
    },
    {
      "id": "el_0d85d67a",
      "type": "process",
      "x": 400,
      "y": 200,
      "width": 100,
      "height": 45,
      "label": "Process Step",
      "properties": {
        "inputs": [{"value": "ctx"}],
        "outputs": [{"value": "ctx"}],
        "steps": [
          {
            "action": "new_model",
            "description": "",
            "keywordParams": []
          }
        ],
        "description": ""
      }
    },
    {
      "id": "el_6hiceujqx",
      "type": "end",
      "x": 400,
      "y": 300,
      "width": 100,
      "height": 45,
      "label": "End",
      "properties": {
        "inputs": [{"value": "ctx"}],
        "outputs": [],
        "description": ""
      }
    }
  ],
  "connections": [
    {
      "id": "conn_0f2da471",
      "from": "el_0de60a01",
      "to": "el_0d85d67a",
      "fromPosition": "bottom",
      "toPosition": "top",
      "label": null
    },
    {
      "id": "conn_ih8jywqux",
      "from": "el_0d85d67a",
      "to": "el_6hiceujqx",
      "fromPosition": "bottom",
      "toPosition": "top",
      "label": null
    }
  ],
  "metadata": {
    "canvas": {
      "width": 2000,
      "height": 1500
    },
    "created_at": "2026-02-11T09:44:25.810Z"
  }
}
```

### Elements Array Structure
Each element in the `elements` array:
```json
{
  "id": "el_<random>",           // Unique element ID
  "type": "start|process|decision|loop|end",
  "x": 400,                       // X position on canvas
  "y": 100,                       // Y position on canvas
  "width": 100,                   // Element width
  "height": 45,                   // Element height
  "label": "Element Label",       // Display name
  "properties": {                 // Type-specific properties
    "inputs": [...],              // Input variables
    "outputs": [...],             // Output variables
    "steps": [...],               // For process type
    "branches": [...],            // For decision type
    "description": ""             // Optional description
  }
}
```

### Element Types

#### 1. Start Element
```json
{
  "type": "start",
  "properties": {
    "inputs": [{"value": "all params"}],
    "outputs": [{"value": "ctx"}],
    "description": ""
  }
}
```

#### 2. Process Element
```json
{
  "type": "process",
  "properties": {
    "inputs": [{"value": "ctx"}],
    "outputs": [{"value": "ctx"}],
    "steps": [
      {
        "action": "new_model",
        "description": "",
        "keywordParams": []
      }
    ],
    "description": ""
  }
}
```

#### 3. Decision Element
```json
{
  "type": "decision",
  "properties": {
    "inputs": [{"value": "ctx"}],
    "branches": [
      {"label": "Yes", "condition": "ctx.valid == true"},
      {"label": "No", "condition": "ctx.valid == false"}
    ],
    "description": ""
  }
}
```

#### 4. Loop Element
```json
{
  "type": "loop",
  "properties": {
    "inputs": [{"value": "ctx"}],
    "outputs": [{"value": "ctx"}],
    "loopCondition": "ctx.items.any?",
    "steps": [
      {"action": "process_item", "keywordParams": []}
    ],
    "description": ""
  }
}
```

#### 5. End Element
```json
{
  "type": "end",
  "properties": {
    "inputs": [{"value": "ctx"}],
    "outputs": [{"value": "result"}],
    "description": ""
  }
}
```

### Connections Array Structure
Each connection in the `connections` array:
```json
{
  "id": "conn_<random>",          // Unique connection ID
  "from": "el_001",                // Source element ID
  "to": "el_002",                  // Target element ID
  "fromPosition": "bottom|top|left|right",
  "toPosition": "top|bottom|left|right",
  "label": "Optional Label"        // Optional connection label
}
```

### Metadata Structure
```json
{
  "canvas": {
    "width": 2000,
    "height": 1500
  },
  "created_at": "2026-02-11T09:44:25.810Z"
}
```

## Complete Record Example (JSON)

### Custom Flowchart
```json
{
  "id": 1,
  "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "Student Enrollment",
  "description": "Process for enrolling new students",
  "flowchart_type": "custom",
  "status": "active",
  "entity_id": 5,
  "customer_id": 12345678,
  "configuration": {
    "elements": [...],
    "connections": [...],
    "metadata": {...}
  },
  "activity": "class StudentEnrollmentActivity < Trailblazer::Activity::Railway\n  step :validate_data\n  step :save_student\nend",
  "created_at": "2026-02-25T10:00:00.000Z",
  "updated_at": "2026-02-25T10:30:00.000Z"
}
```

### Blueprint Flowchart
```json
{
  "id": 29,
  "uuid": "8151cd9c-b071-431d-b250-0e6e56bf63dd",
  "name": "Create Entity Entry",
  "description": "Blueprint to create a new entry for entity",
  "flowchart_type": "blueprint",
  "status": "active",
  "entity_id": null,
  "customer_id": null,
  "configuration": {
    "elements": [...],
    "connections": [...],
    "metadata": {...}
  },
  "activity": "class CreateEntityEntryActivity < Trailblazer::Activity::Railway\n  step :new_model\n  step :build_contract\n  step :validate_contract\n  step :save_model\nend",
  "created_at": "2026-02-11T07:22:34.000Z",
  "updated_at": "2026-02-11T09:44:23.000Z"
}
```

## Ruby Model Access

### Basic Access
```ruby
flowchart = Flowchart.find(1)

flowchart.id              # => 1
flowchart.uuid            # => "a1b2c3d4-..."
flowchart.name            # => "Student Enrollment"
flowchart.description     # => "Process for enrolling new students"
```

### Enum Methods
```ruby
# Type
flowchart.flowchart_type  # => "custom"
flowchart.custom?         # => true
flowchart.blueprint?      # => false

# Status
flowchart.status          # => "active"
flowchart.active?         # => true
flowchart.deleted?        # => false
```

### Configuration Access
```ruby
# Get configuration as parsed JSON
flowchart.configuration_json

# Convenience methods
flowchart.elements        # => Array of elements
flowchart.connections     # => Array of connections
flowchart.metadata        # => Metadata hash
flowchart.canvas_size     # => {"width"=>2000, "height"=>1500}
```

### Associations
```ruby
flowchart.entity          # => Entity object (if custom type)
flowchart.customer        # => Customer object (if custom type)
```

### Scopes
```ruby
# Get recent flowcharts (custom first, then by updated_at)
Flowchart.recent

# Get by name alphabetically
Flowchart.by_name

# Get only blueprints
Flowchart.blueprints

# Get accessible flowcharts (current customer's + blueprints)
Flowchart.accessible

# Active flowcharts only (default scope)
Flowchart.all  # => Only active flowcharts

# Include deleted
Flowchart.unscoped  # => All flowcharts including deleted
```

## Validations

### Name
- **Required**
- Length: 1-100 characters
- Unique within customer (for custom)
- Globally unique (for blueprint)

### UUID
- **Required**
- Auto-generated if not provided
- Unique within customer (for custom)
- Globally unique (for blueprint)

### Configuration
- **Required**
- Must be valid JSON
- Must contain: `elements`, `connections`, `metadata` keys
- `elements` must be an array
- `connections` must be an array
- `metadata` must be an object

### Type-Specific
- **Custom flowcharts**:
  - `entity_id` is required
  - `customer_id` is required
- **Blueprint flowcharts**:
  - `entity_id` must be NULL
  - `customer_id` must be NULL

## Database Indices

| Index Name | Columns | Unique | Where Clause |
|------------|---------|--------|--------------|
| PRIMARY | id | Yes | - |
| index_flowcharts_on_uuid | uuid | Yes | - |
| index_flowcharts_on_customer_id_and_uuid_for_custom | customer_id, uuid | Yes | customer_id IS NOT NULL |
| index_flowcharts_on_customer_id | customer_id | No | - |
| index_flowcharts_on_entity_id | entity_id | No | - |
| index_flowcharts_on_status | status | No | - |
| index_flowcharts_on_flowchart_type | flowchart_type | No | - |
| index_flowcharts_on_name | name | No | - |
| index_flowcharts_on_created_at | created_at | No | - |

## Use Cases

### 1. Create Custom Flowchart
```ruby
flowchart = Flowchart.create!(
  name: "Order Processing",
  description: "Handle customer orders",
  flowchart_type: :custom,
  entity_id: 5,
  customer_id: 12345678,
  configuration: {
    elements: [...],
    connections: [...],
    metadata: {
      canvas: { width: 2000, height: 1500 }
    }
  }.to_json
)
```

### 2. Create Blueprint Flowchart
```ruby
flowchart = Flowchart.create!(
  name: "CRUD Template",
  description: "Standard CRUD operations",
  flowchart_type: :blueprint,
  entity_id: nil,
  customer_id: nil,
  configuration: {...}.to_json
)
```

### 3. Access via UUID
```ruby
# URL: /:customer_id/:uuid/...
flowchart = Flowchart.find_by(uuid: "8151cd9c-b071-431d-b250-0e6e56bf63dd")
```

### 4. Query Accessible Flowcharts
```ruby
# Within tenant context
Current.customer_id = 12345678
flowcharts = Flowchart.accessible  # Customer's flowcharts + blueprints
```

### 5. Soft Delete
```ruby
flowchart.soft_delete  # Sets status to 'deleted'
flowchart.restore      # Sets status back to 'active'
```

## Activity Generation

The `activity` field is auto-generated from the flowchart configuration:

```ruby
# Before save callback generates:
flowchart.activity = ActivityGenerator.new(flowchart).generate

# Result example:
# frozen_string_literal: true
#
# Generated Activity for: Create Entity Entry
# Blueprint (Template) - no entity bound

class CreateEntityEntryActivity < Trailblazer::Activity::Railway
  step :new_model
  step :build_contract
  step :validate_contract
  step :save_model
end
```

## Diagram Generation

Generate Mermaid diagram on-the-fly:
```ruby
diagram = flowchart.diagram
# => Mermaid syntax string for visualization
```

## URL Structure

### Custom Flowchart Execution
```
/:customer_id/:uuid/:entity_slug
/:customer_id/:uuid/:entity_slug/:id
```

Example:
```
/12345678/a1b2c3d4-e5f6-7890-abcd-ef1234567890/students
/12345678/a1b2c3d4-e5f6-7890-abcd-ef1234567890/students/42
```

### Blueprint Flowchart (No Entity)
```
/:customer_id/:uuid
```

Example:
```
/12345678/8151cd9c-b071-431d-b250-0e6e56bf63dd
```
