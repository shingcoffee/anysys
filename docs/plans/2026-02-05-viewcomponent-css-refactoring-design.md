# ViewComponent CSS Refactoring Design

## Overview

Refactor Rails views and ViewComponents to standardize CSS patterns, create reusable UI components, and reorganize application.css for maintainability.

## Goals

1. Create reusable ViewComponents for common UI patterns (buttons, badges, forms, modals, cards)
2. Standardize inconsistent styling across the application
3. Remove duplicate CSS and reorganize application.css
4. Full RSpec test coverage for new components

## New Components

### ButtonComponent

Variants: primary, secondary, danger, ghost
Sizes: sm, md, lg
Features: supports `<button>` and `<a>` tags, optional icons, disabled state

```ruby
VARIANTS = {
  primary:   { base: "bg-indigo-600 text-white hover:bg-indigo-700 focus:ring-indigo-600" },
  secondary: { base: "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50" },
  danger:    { base: "bg-red-600 text-white hover:bg-red-700 focus:ring-red-600" },
  ghost:     { base: "text-gray-600 hover:text-gray-900 hover:bg-gray-100" }
}
```

### BadgeComponent

Variants: default, primary, success, warning, danger, info, purple
Sizes: sm, md

```ruby
VARIANTS = {
  default:  "bg-gray-100 text-gray-800",
  primary:  "bg-indigo-100 text-indigo-800",
  success:  "bg-green-100 text-green-800",
  warning:  "bg-yellow-100 text-yellow-800",
  danger:   "bg-red-100 text-red-800",
  info:     "bg-blue-100 text-blue-800",
  purple:   "bg-purple-100 text-purple-800"
}
```

### FormInputComponent

Types: text, email, password, textarea, select
Features: label, error state, placeholder, disabled state

### CardComponent

Variants: default (shadow), bordered, flat
Padding options: none, sm, md, lg

### ModalComponent

Sizes: sm, md, lg, xl, full
Slots: header, body, footer

## CSS Reorganization

### application.css Changes

1. Remove duplicate scrollbar CSS (lines 356-378)
2. Add section comments for organization
3. Add utility classes:
   - `.custom-scrollbar` - reusable scrollbar styling
   - `.focus-ring` - standardized focus states

### Section Structure

```
1. CSS Custom Properties
2. Base Styles
3. Component Styles (canvas, flowchart elements)
4. Utility Classes
5. Animations & Transitions
```

## Refactoring Targets

### Views to Update

- `flowcharts/index.html.erb` - use ButtonComponent, CardComponent
- `entities/index.html.erb` - use ButtonComponent, CardComponent
- `flowcharts/show.html.erb` - use BadgeComponent, ButtonComponent
- `shared/_property_editor_modal.html.erb` - use ModalComponent, FormInputComponent, ButtonComponent

### Existing Components to Update

- `FlowchartInfoCardComponent` - use BadgeComponent
- `FlowchartListTableComponent` - use BadgeComponent
- `ActivityTraceComponent` - use BadgeComponent, .custom-scrollbar

## Implementation Phases

### Phase 1: Foundation
- Clean up application.css
- Add utility classes

### Phase 2: New Components
- ButtonComponent + specs
- BadgeComponent + specs
- FormInputComponent + specs
- CardComponent + specs
- ModalComponent + specs

### Phase 3: Refactor Existing
- Update existing components to use new components
- Refactor views to use new components

### Phase 4: Verification
- Run full test suite
- Visual verification

## Testing Strategy

Each new component requires:
- All variants render correctly
- Size options work
- HTML attributes merge properly
- Slots render content (ModalComponent)
- Accessibility attributes present
