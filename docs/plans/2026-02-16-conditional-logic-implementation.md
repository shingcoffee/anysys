# Conditional Logic System Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a JotForm-style rule-based conditional logic system with formula calculations for the page builder.

**Architecture:** Rule-based system where rules contain conditions (triggers) and actions (effects). Separate formula engine for calculated fields. Client-side JavaScript evaluation at runtime. Migration layer for backward compatibility with existing field-level conditions.

**Tech Stack:** Ruby/Rails, StimulusJS, ViewComponent, RSpec, Jest (for JS tests)

---

## Phase 1: Core Libraries (JavaScript)

### Task 1: Condition Evaluator - Basic Operators

**Files:**
- Create: `app/javascript/lib/condition_evaluator.js`
- Create: `spec/javascript/lib/condition_evaluator_spec.js`

**Step 1: Write failing test for equals operator**

Create `spec/javascript/lib/condition_evaluator_spec.js`:
```javascript
import { ConditionEvaluator } from '../../../app/javascript/lib/condition_evaluator'

describe('ConditionEvaluator', () => {
  describe('evaluateCondition', () => {
    describe('equals operator', () => {
      it('returns true when values match', () => {
        const evaluator = new ConditionEvaluator({ status: 'active' })
        const result = evaluator.evaluateCondition({
          field_id: 'status',
          operator: 'equals',
          value: 'active'
        })
        expect(result).toBe(true)
      })

      it('returns false when values do not match', () => {
        const evaluator = new ConditionEvaluator({ status: 'inactive' })
        const result = evaluator.evaluateCondition({
          field_id: 'status',
          operator: 'equals',
          value: 'active'
        })
        expect(result).toBe(false)
      })
    })
  })
})
```

**Step 2: Run test to verify it fails**

Run: `yarn jest spec/javascript/lib/condition_evaluator_spec.js`
Expected: FAIL with "Cannot find module"

**Step 3: Write minimal implementation**

Create `app/javascript/lib/condition_evaluator.js`:
```javascript
export class ConditionEvaluator {
  constructor(fieldValues = {}) {
    this.values = fieldValues
  }

  evaluateCondition(condition) {
    const fieldValue = this.values[condition.field_id]
    const compareValue = condition.value

    switch (condition.operator) {
      case 'equals':
        return fieldValue == compareValue
      default:
        return false
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `yarn jest spec/javascript/lib/condition_evaluator_spec.js`
Expected: PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/condition_evaluator.js spec/javascript/lib/condition_evaluator_spec.js
git commit -m "feat: add ConditionEvaluator with equals operator"
```

---

### Task 2: Condition Evaluator - All Operators

**Files:**
- Modify: `app/javascript/lib/condition_evaluator.js`
- Modify: `spec/javascript/lib/condition_evaluator_spec.js`

**Step 1: Write failing tests for remaining operators**

Add to `spec/javascript/lib/condition_evaluator_spec.js`:
```javascript
describe('not_equals operator', () => {
  it('returns true when values differ', () => {
    const evaluator = new ConditionEvaluator({ status: 'inactive' })
    expect(evaluator.evaluateCondition({
      field_id: 'status', operator: 'not_equals', value: 'active'
    })).toBe(true)
  })
})

describe('contains operator', () => {
  it('returns true when string contains substring', () => {
    const evaluator = new ConditionEvaluator({ email: 'john@example.com' })
    expect(evaluator.evaluateCondition({
      field_id: 'email', operator: 'contains', value: 'example'
    })).toBe(true)
  })
})

describe('not_contains operator', () => {
  it('returns true when string does not contain substring', () => {
    const evaluator = new ConditionEvaluator({ email: 'john@gmail.com' })
    expect(evaluator.evaluateCondition({
      field_id: 'email', operator: 'not_contains', value: 'example'
    })).toBe(true)
  })
})

describe('starts_with operator', () => {
  it('returns true when string starts with prefix', () => {
    const evaluator = new ConditionEvaluator({ code: 'ABC123' })
    expect(evaluator.evaluateCondition({
      field_id: 'code', operator: 'starts_with', value: 'ABC'
    })).toBe(true)
  })
})

describe('ends_with operator', () => {
  it('returns true when string ends with suffix', () => {
    const evaluator = new ConditionEvaluator({ file: 'report.pdf' })
    expect(evaluator.evaluateCondition({
      field_id: 'file', operator: 'ends_with', value: '.pdf'
    })).toBe(true)
  })
})

describe('greater_than operator', () => {
  it('returns true when value is greater', () => {
    const evaluator = new ConditionEvaluator({ age: 25 })
    expect(evaluator.evaluateCondition({
      field_id: 'age', operator: 'greater_than', value: 18
    })).toBe(true)
  })
})

describe('less_than operator', () => {
  it('returns true when value is less', () => {
    const evaluator = new ConditionEvaluator({ age: 15 })
    expect(evaluator.evaluateCondition({
      field_id: 'age', operator: 'less_than', value: 18
    })).toBe(true)
  })
})

describe('greater_or_equal operator', () => {
  it('returns true when value is equal', () => {
    const evaluator = new ConditionEvaluator({ age: 18 })
    expect(evaluator.evaluateCondition({
      field_id: 'age', operator: 'greater_or_equal', value: 18
    })).toBe(true)
  })
})

describe('less_or_equal operator', () => {
  it('returns true when value is equal', () => {
    const evaluator = new ConditionEvaluator({ age: 18 })
    expect(evaluator.evaluateCondition({
      field_id: 'age', operator: 'less_or_equal', value: 18
    })).toBe(true)
  })
})

describe('between operator', () => {
  it('returns true when value is in range', () => {
    const evaluator = new ConditionEvaluator({ age: 25 })
    expect(evaluator.evaluateCondition({
      field_id: 'age', operator: 'between', value: [18, 65]
    })).toBe(true)
  })

  it('returns true when value equals boundary', () => {
    const evaluator = new ConditionEvaluator({ age: 18 })
    expect(evaluator.evaluateCondition({
      field_id: 'age', operator: 'between', value: [18, 65]
    })).toBe(true)
  })
})

describe('is_empty operator', () => {
  it('returns true for empty string', () => {
    const evaluator = new ConditionEvaluator({ name: '' })
    expect(evaluator.evaluateCondition({
      field_id: 'name', operator: 'is_empty'
    })).toBe(true)
  })

  it('returns true for null', () => {
    const evaluator = new ConditionEvaluator({ name: null })
    expect(evaluator.evaluateCondition({
      field_id: 'name', operator: 'is_empty'
    })).toBe(true)
  })

  it('returns true for undefined', () => {
    const evaluator = new ConditionEvaluator({})
    expect(evaluator.evaluateCondition({
      field_id: 'name', operator: 'is_empty'
    })).toBe(true)
  })

  it('returns false for zero', () => {
    const evaluator = new ConditionEvaluator({ count: 0 })
    expect(evaluator.evaluateCondition({
      field_id: 'count', operator: 'is_empty'
    })).toBe(false)
  })
})

describe('is_not_empty operator', () => {
  it('returns true for non-empty value', () => {
    const evaluator = new ConditionEvaluator({ name: 'John' })
    expect(evaluator.evaluateCondition({
      field_id: 'name', operator: 'is_not_empty'
    })).toBe(true)
  })
})

describe('is_selected operator', () => {
  it('returns true when option is in array', () => {
    const evaluator = new ConditionEvaluator({ colors: ['red', 'blue'] })
    expect(evaluator.evaluateCondition({
      field_id: 'colors', operator: 'is_selected', value: 'red'
    })).toBe(true)
  })

  it('returns true for boolean true', () => {
    const evaluator = new ConditionEvaluator({ agreed: true })
    expect(evaluator.evaluateCondition({
      field_id: 'agreed', operator: 'is_selected', value: true
    })).toBe(true)
  })
})

describe('is_not_selected operator', () => {
  it('returns true when option is not in array', () => {
    const evaluator = new ConditionEvaluator({ colors: ['red', 'blue'] })
    expect(evaluator.evaluateCondition({
      field_id: 'colors', operator: 'is_not_selected', value: 'green'
    })).toBe(true)
  })
})

describe('matches_regex operator', () => {
  it('returns true when pattern matches', () => {
    const evaluator = new ConditionEvaluator({ phone: '123-456-7890' })
    expect(evaluator.evaluateCondition({
      field_id: 'phone', operator: 'matches_regex', value: '^\\d{3}-\\d{3}-\\d{4}$'
    })).toBe(true)
  })
})
```

**Step 2: Run tests to verify they fail**

Run: `yarn jest spec/javascript/lib/condition_evaluator_spec.js`
Expected: Multiple FAIL

**Step 3: Implement all operators**

Update `app/javascript/lib/condition_evaluator.js`:
```javascript
export class ConditionEvaluator {
  constructor(fieldValues = {}) {
    this.values = fieldValues
  }

  evaluateCondition(condition) {
    const fieldValue = this.values[condition.field_id]
    const compareValue = condition.value

    switch (condition.operator) {
      case 'equals':
        return fieldValue == compareValue

      case 'not_equals':
        return fieldValue != compareValue

      case 'contains':
        return String(fieldValue ?? '').includes(String(compareValue ?? ''))

      case 'not_contains':
        return !String(fieldValue ?? '').includes(String(compareValue ?? ''))

      case 'starts_with':
        return String(fieldValue ?? '').startsWith(String(compareValue ?? ''))

      case 'ends_with':
        return String(fieldValue ?? '').endsWith(String(compareValue ?? ''))

      case 'greater_than':
        return Number(fieldValue) > Number(compareValue)

      case 'less_than':
        return Number(fieldValue) < Number(compareValue)

      case 'greater_or_equal':
        return Number(fieldValue) >= Number(compareValue)

      case 'less_or_equal':
        return Number(fieldValue) <= Number(compareValue)

      case 'between':
        const num = Number(fieldValue)
        return num >= Number(compareValue[0]) && num <= Number(compareValue[1])

      case 'is_empty':
        return fieldValue === null || fieldValue === undefined || fieldValue === ''

      case 'is_not_empty':
        return fieldValue !== null && fieldValue !== undefined && fieldValue !== ''

      case 'is_selected':
        if (Array.isArray(fieldValue)) {
          return fieldValue.includes(compareValue)
        }
        return fieldValue === compareValue

      case 'is_not_selected':
        if (Array.isArray(fieldValue)) {
          return !fieldValue.includes(compareValue)
        }
        return fieldValue !== compareValue

      case 'matches_regex':
        try {
          const regex = new RegExp(compareValue)
          return regex.test(String(fieldValue ?? ''))
        } catch {
          return false
        }

      default:
        return false
    }
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/condition_evaluator_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/condition_evaluator.js spec/javascript/lib/condition_evaluator_spec.js
git commit -m "feat: add all 16 condition operators to ConditionEvaluator"
```

---

### Task 3: Condition Evaluator - Nested Groups

**Files:**
- Modify: `app/javascript/lib/condition_evaluator.js`
- Modify: `spec/javascript/lib/condition_evaluator_spec.js`

**Step 1: Write failing tests for group evaluation**

Add to `spec/javascript/lib/condition_evaluator_spec.js`:
```javascript
describe('evaluate (full condition tree)', () => {
  describe('single group with ALL logic', () => {
    it('returns true when all conditions match', () => {
      const evaluator = new ConditionEvaluator({ a: 1, b: 2 })
      const conditions = {
        logic: 'all',
        groups: [{
          logic: 'all',
          items: [
            { field_id: 'a', operator: 'equals', value: 1 },
            { field_id: 'b', operator: 'equals', value: 2 }
          ]
        }]
      }
      expect(evaluator.evaluate(conditions)).toBe(true)
    })

    it('returns false when one condition fails', () => {
      const evaluator = new ConditionEvaluator({ a: 1, b: 999 })
      const conditions = {
        logic: 'all',
        groups: [{
          logic: 'all',
          items: [
            { field_id: 'a', operator: 'equals', value: 1 },
            { field_id: 'b', operator: 'equals', value: 2 }
          ]
        }]
      }
      expect(evaluator.evaluate(conditions)).toBe(false)
    })
  })

  describe('single group with ANY logic', () => {
    it('returns true when one condition matches', () => {
      const evaluator = new ConditionEvaluator({ a: 1, b: 999 })
      const conditions = {
        logic: 'all',
        groups: [{
          logic: 'any',
          items: [
            { field_id: 'a', operator: 'equals', value: 1 },
            { field_id: 'b', operator: 'equals', value: 2 }
          ]
        }]
      }
      expect(evaluator.evaluate(conditions)).toBe(true)
    })
  })

  describe('multiple groups with ANY logic', () => {
    it('returns true when one group matches (OR between groups)', () => {
      const evaluator = new ConditionEvaluator({ a: 1, b: 999, c: 999 })
      const conditions = {
        logic: 'any',
        groups: [
          {
            logic: 'all',
            items: [{ field_id: 'a', operator: 'equals', value: 1 }]
          },
          {
            logic: 'all',
            items: [{ field_id: 'b', operator: 'equals', value: 2 }]
          }
        ]
      }
      expect(evaluator.evaluate(conditions)).toBe(true)
    })
  })

  describe('multiple groups with ALL logic', () => {
    it('returns true only when all groups match (AND between groups)', () => {
      const evaluator = new ConditionEvaluator({ a: 1, b: 2 })
      const conditions = {
        logic: 'all',
        groups: [
          {
            logic: 'all',
            items: [{ field_id: 'a', operator: 'equals', value: 1 }]
          },
          {
            logic: 'all',
            items: [{ field_id: 'b', operator: 'equals', value: 2 }]
          }
        ]
      }
      expect(evaluator.evaluate(conditions)).toBe(true)
    })

    it('returns false when one group fails', () => {
      const evaluator = new ConditionEvaluator({ a: 1, b: 999 })
      const conditions = {
        logic: 'all',
        groups: [
          {
            logic: 'all',
            items: [{ field_id: 'a', operator: 'equals', value: 1 }]
          },
          {
            logic: 'all',
            items: [{ field_id: 'b', operator: 'equals', value: 2 }]
          }
        ]
      }
      expect(evaluator.evaluate(conditions)).toBe(false)
    })
  })

  describe('empty/null conditions', () => {
    it('returns true for empty groups array', () => {
      const evaluator = new ConditionEvaluator({})
      expect(evaluator.evaluate({ logic: 'all', groups: [] })).toBe(true)
    })

    it('returns true for null conditions', () => {
      const evaluator = new ConditionEvaluator({})
      expect(evaluator.evaluate(null)).toBe(true)
    })

    it('returns true for undefined conditions', () => {
      const evaluator = new ConditionEvaluator({})
      expect(evaluator.evaluate(undefined)).toBe(true)
    })
  })
})
```

**Step 2: Run tests to verify they fail**

Run: `yarn jest spec/javascript/lib/condition_evaluator_spec.js`
Expected: FAIL with "evaluate is not a function"

**Step 3: Implement evaluate method**

Add to `app/javascript/lib/condition_evaluator.js`:
```javascript
export class ConditionEvaluator {
  constructor(fieldValues = {}) {
    this.values = fieldValues
  }

  evaluate(conditions) {
    if (!conditions?.groups?.length) {
      return true
    }

    const groupResults = conditions.groups.map(group => this.evaluateGroup(group))

    return conditions.logic === 'all'
      ? groupResults.every(Boolean)
      : groupResults.some(Boolean)
  }

  evaluateGroup(group) {
    if (!group?.items?.length) {
      return true
    }

    const itemResults = group.items.map(item => this.evaluateCondition(item))

    return group.logic === 'all'
      ? itemResults.every(Boolean)
      : itemResults.some(Boolean)
  }

  evaluateCondition(condition) {
    // ... existing implementation
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/condition_evaluator_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/condition_evaluator.js spec/javascript/lib/condition_evaluator_spec.js
git commit -m "feat: add nested group evaluation to ConditionEvaluator"
```

---

### Task 4: Formula Engine - Tokenizer

**Files:**
- Create: `app/javascript/lib/formula_engine.js`
- Create: `spec/javascript/lib/formula_engine_spec.js`

**Step 1: Write failing test for tokenizer**

Create `spec/javascript/lib/formula_engine_spec.js`:
```javascript
import { FormulaEngine } from '../../../app/javascript/lib/formula_engine'

describe('FormulaEngine', () => {
  describe('tokenize', () => {
    it('tokenizes numbers', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('42')).toEqual([
        { type: 'NUMBER', value: 42 }
      ])
    })

    it('tokenizes decimal numbers', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('3.14')).toEqual([
        { type: 'NUMBER', value: 3.14 }
      ])
    })

    it('tokenizes strings', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('"hello"')).toEqual([
        { type: 'STRING', value: 'hello' }
      ])
    })

    it('tokenizes identifiers (field references)', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('price')).toEqual([
        { type: 'IDENTIFIER', value: 'price' }
      ])
    })

    it('tokenizes operators', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('a + b')).toEqual([
        { type: 'IDENTIFIER', value: 'a' },
        { type: 'OPERATOR', value: '+' },
        { type: 'IDENTIFIER', value: 'b' }
      ])
    })

    it('tokenizes comparison operators', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('a >= b')).toEqual([
        { type: 'IDENTIFIER', value: 'a' },
        { type: 'OPERATOR', value: '>=' },
        { type: 'IDENTIFIER', value: 'b' }
      ])
    })

    it('tokenizes function calls', () => {
      const engine = new FormulaEngine({})
      expect(engine.tokenize('SUM(a, b)')).toEqual([
        { type: 'FUNCTION', value: 'SUM' },
        { type: 'LPAREN', value: '(' },
        { type: 'IDENTIFIER', value: 'a' },
        { type: 'COMMA', value: ',' },
        { type: 'IDENTIFIER', value: 'b' },
        { type: 'RPAREN', value: ')' }
      ])
    })

    it('tokenizes complex expressions', () => {
      const engine = new FormulaEngine({})
      const tokens = engine.tokenize('price * quantity + 10')
      expect(tokens).toEqual([
        { type: 'IDENTIFIER', value: 'price' },
        { type: 'OPERATOR', value: '*' },
        { type: 'IDENTIFIER', value: 'quantity' },
        { type: 'OPERATOR', value: '+' },
        { type: 'NUMBER', value: 10 }
      ])
    })
  })
})
```

**Step 2: Run test to verify it fails**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: FAIL with "Cannot find module"

**Step 3: Implement tokenizer**

Create `app/javascript/lib/formula_engine.js`:
```javascript
export class FormulaEngine {
  constructor(fieldValues = {}) {
    this.values = fieldValues
    this.functions = this.registerFunctions()
  }

  tokenize(formula) {
    const tokens = []
    let pos = 0

    while (pos < formula.length) {
      // Skip whitespace
      if (/\s/.test(formula[pos])) {
        pos++
        continue
      }

      // Numbers (including decimals)
      if (/\d/.test(formula[pos])) {
        let num = ''
        while (pos < formula.length && /[\d.]/.test(formula[pos])) {
          num += formula[pos++]
        }
        tokens.push({ type: 'NUMBER', value: parseFloat(num) })
        continue
      }

      // Strings
      if (formula[pos] === '"' || formula[pos] === "'") {
        const quote = formula[pos++]
        let str = ''
        while (pos < formula.length && formula[pos] !== quote) {
          str += formula[pos++]
        }
        pos++ // Skip closing quote
        tokens.push({ type: 'STRING', value: str })
        continue
      }

      // Identifiers and functions
      if (/[a-zA-Z_]/.test(formula[pos])) {
        let ident = ''
        while (pos < formula.length && /[a-zA-Z0-9_]/.test(formula[pos])) {
          ident += formula[pos++]
        }
        // Check if it's a function (followed by parenthesis)
        const isFunction = formula[pos] === '('
        tokens.push({
          type: isFunction ? 'FUNCTION' : 'IDENTIFIER',
          value: ident
        })
        continue
      }

      // Two-character operators
      const twoChar = formula.slice(pos, pos + 2)
      if (['>=', '<=', '==', '!=', '&&', '||'].includes(twoChar)) {
        tokens.push({ type: 'OPERATOR', value: twoChar })
        pos += 2
        continue
      }

      // Single-character operators and punctuation
      const char = formula[pos]
      if (['+', '-', '*', '/', '%', '>', '<'].includes(char)) {
        tokens.push({ type: 'OPERATOR', value: char })
        pos++
        continue
      }

      if (char === '(') {
        tokens.push({ type: 'LPAREN', value: '(' })
        pos++
        continue
      }

      if (char === ')') {
        tokens.push({ type: 'RPAREN', value: ')' })
        pos++
        continue
      }

      if (char === ',') {
        tokens.push({ type: 'COMMA', value: ',' })
        pos++
        continue
      }

      // Unknown character - skip
      pos++
    }

    return tokens
  }

  registerFunctions() {
    return {}
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/formula_engine.js spec/javascript/lib/formula_engine_spec.js
git commit -m "feat: add FormulaEngine tokenizer"
```

---

### Task 5: Formula Engine - Parser and Basic Arithmetic

**Files:**
- Modify: `app/javascript/lib/formula_engine.js`
- Modify: `spec/javascript/lib/formula_engine_spec.js`

**Step 1: Write failing tests for parser and evaluate**

Add to `spec/javascript/lib/formula_engine_spec.js`:
```javascript
describe('evaluate', () => {
  describe('basic arithmetic', () => {
    it('evaluates addition', () => {
      const engine = new FormulaEngine({ a: 5, b: 3 })
      expect(engine.evaluate('a + b')).toBe(8)
    })

    it('evaluates subtraction', () => {
      const engine = new FormulaEngine({ a: 10, b: 3 })
      expect(engine.evaluate('a - b')).toBe(7)
    })

    it('evaluates multiplication', () => {
      const engine = new FormulaEngine({ a: 4, b: 5 })
      expect(engine.evaluate('a * b')).toBe(20)
    })

    it('evaluates division', () => {
      const engine = new FormulaEngine({ a: 20, b: 4 })
      expect(engine.evaluate('a / b')).toBe(5)
    })

    it('respects operator precedence (* before +)', () => {
      const engine = new FormulaEngine({ a: 2, b: 3, c: 4 })
      expect(engine.evaluate('a + b * c')).toBe(14)
    })

    it('respects parentheses', () => {
      const engine = new FormulaEngine({ a: 2, b: 3, c: 4 })
      expect(engine.evaluate('(a + b) * c')).toBe(20)
    })

    it('evaluates literal numbers', () => {
      const engine = new FormulaEngine({})
      expect(engine.evaluate('10 + 5')).toBe(15)
    })

    it('evaluates mixed field refs and literals', () => {
      const engine = new FormulaEngine({ price: 100 })
      expect(engine.evaluate('price * 0.1')).toBe(10)
    })
  })

  describe('field references', () => {
    it('resolves field values', () => {
      const engine = new FormulaEngine({ quantity: 5, price: 10 })
      expect(engine.evaluate('quantity * price')).toBe(50)
    })

    it('returns null for missing field', () => {
      const engine = new FormulaEngine({})
      expect(engine.evaluate('missing_field + 1')).toBeNull()
    })
  })

  describe('comparison operators', () => {
    it('evaluates greater than', () => {
      const engine = new FormulaEngine({ age: 25 })
      expect(engine.evaluate('age > 18')).toBe(true)
    })

    it('evaluates less than', () => {
      const engine = new FormulaEngine({ age: 15 })
      expect(engine.evaluate('age < 18')).toBe(true)
    })

    it('evaluates equality', () => {
      const engine = new FormulaEngine({ status: 'active' })
      expect(engine.evaluate('status == "active"')).toBe(true)
    })
  })

  describe('error handling', () => {
    it('returns null for empty formula', () => {
      const engine = new FormulaEngine({})
      expect(engine.evaluate('')).toBeNull()
    })

    it('returns null for null formula', () => {
      const engine = new FormulaEngine({})
      expect(engine.evaluate(null)).toBeNull()
    })

    it('returns 0 for division by zero', () => {
      const engine = new FormulaEngine({ a: 10, b: 0 })
      expect(engine.evaluate('a / b')).toBe(0)
    })
  })
})
```

**Step 2: Run tests to verify they fail**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: Multiple FAIL

**Step 3: Implement parser and evaluate**

Update `app/javascript/lib/formula_engine.js`:
```javascript
export class FormulaEngine {
  constructor(fieldValues = {}) {
    this.values = fieldValues
    this.functions = this.registerFunctions()
  }

  evaluate(formula) {
    if (!formula?.trim()) return null

    try {
      const tokens = this.tokenize(formula)
      const ast = this.parse(tokens)
      return this.execute(ast)
    } catch (error) {
      console.warn('Formula evaluation error:', error)
      return null
    }
  }

  tokenize(formula) {
    // ... existing implementation
  }

  parse(tokens) {
    let pos = 0

    const parseExpression = () => {
      return parseComparison()
    }

    const parseComparison = () => {
      let left = parseAdditive()

      while (pos < tokens.length &&
             tokens[pos].type === 'OPERATOR' &&
             ['>', '<', '>=', '<=', '==', '!='].includes(tokens[pos].value)) {
        const op = tokens[pos++].value
        const right = parseAdditive()
        left = { type: 'BINARY', operator: op, left, right }
      }

      return left
    }

    const parseAdditive = () => {
      let left = parseMultiplicative()

      while (pos < tokens.length &&
             tokens[pos].type === 'OPERATOR' &&
             ['+', '-'].includes(tokens[pos].value)) {
        const op = tokens[pos++].value
        const right = parseMultiplicative()
        left = { type: 'BINARY', operator: op, left, right }
      }

      return left
    }

    const parseMultiplicative = () => {
      let left = parsePrimary()

      while (pos < tokens.length &&
             tokens[pos].type === 'OPERATOR' &&
             ['*', '/', '%'].includes(tokens[pos].value)) {
        const op = tokens[pos++].value
        const right = parsePrimary()
        left = { type: 'BINARY', operator: op, left, right }
      }

      return left
    }

    const parsePrimary = () => {
      const token = tokens[pos]

      if (!token) {
        throw new Error('Unexpected end of expression')
      }

      // Parenthesized expression
      if (token.type === 'LPAREN') {
        pos++
        const expr = parseExpression()
        if (tokens[pos]?.type !== 'RPAREN') {
          throw new Error('Expected closing parenthesis')
        }
        pos++
        return expr
      }

      // Number literal
      if (token.type === 'NUMBER') {
        pos++
        return { type: 'LITERAL', value: token.value }
      }

      // String literal
      if (token.type === 'STRING') {
        pos++
        return { type: 'LITERAL', value: token.value }
      }

      // Function call
      if (token.type === 'FUNCTION') {
        const name = token.value
        pos++ // function name
        pos++ // opening paren
        const args = []

        while (tokens[pos]?.type !== 'RPAREN') {
          args.push(parseExpression())
          if (tokens[pos]?.type === 'COMMA') {
            pos++
          }
        }
        pos++ // closing paren

        return { type: 'CALL', name, args }
      }

      // Identifier (field reference)
      if (token.type === 'IDENTIFIER') {
        pos++
        return { type: 'IDENTIFIER', name: token.value }
      }

      throw new Error(`Unexpected token: ${token.type}`)
    }

    return parseExpression()
  }

  execute(node) {
    if (!node) return null

    switch (node.type) {
      case 'LITERAL':
        return node.value

      case 'IDENTIFIER': {
        const value = this.values[node.name]
        if (value === undefined) return null
        return value
      }

      case 'BINARY': {
        const left = this.execute(node.left)
        const right = this.execute(node.right)

        if (left === null || right === null) {
          // Allow comparisons with null
          if (['==', '!='].includes(node.operator)) {
            if (node.operator === '==') return left === right
            if (node.operator === '!=') return left !== right
          }
          return null
        }

        switch (node.operator) {
          case '+': return Number(left) + Number(right)
          case '-': return Number(left) - Number(right)
          case '*': return Number(left) * Number(right)
          case '/': return right === 0 ? 0 : Number(left) / Number(right)
          case '%': return Number(left) % Number(right)
          case '>': return Number(left) > Number(right)
          case '<': return Number(left) < Number(right)
          case '>=': return Number(left) >= Number(right)
          case '<=': return Number(left) <= Number(right)
          case '==': return left == right
          case '!=': return left != right
          default: return null
        }
      }

      case 'CALL': {
        const func = this.functions[node.name]
        if (!func) {
          console.warn(`Unknown function: ${node.name}`)
          return null
        }
        const args = node.args.map(arg => this.execute(arg))
        return func(...args)
      }

      default:
        return null
    }
  }

  registerFunctions() {
    return {}
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/formula_engine.js spec/javascript/lib/formula_engine_spec.js
git commit -m "feat: add FormulaEngine parser with basic arithmetic"
```

---

### Task 6: Formula Engine - Math Functions

**Files:**
- Modify: `app/javascript/lib/formula_engine.js`
- Modify: `spec/javascript/lib/formula_engine_spec.js`

**Step 1: Write failing tests for math functions**

Add to `spec/javascript/lib/formula_engine_spec.js`:
```javascript
describe('math functions', () => {
  it('evaluates SUM', () => {
    const engine = new FormulaEngine({ a: 1, b: 2, c: 3 })
    expect(engine.evaluate('SUM(a, b, c)')).toBe(6)
  })

  it('evaluates SUM with literals', () => {
    const engine = new FormulaEngine({})
    expect(engine.evaluate('SUM(10, 20, 30)')).toBe(60)
  })

  it('evaluates SUBTRACT', () => {
    const engine = new FormulaEngine({ total: 100, discount: 20 })
    expect(engine.evaluate('SUBTRACT(total, discount)')).toBe(80)
  })

  it('evaluates MULTIPLY', () => {
    const engine = new FormulaEngine({ qty: 5, price: 10 })
    expect(engine.evaluate('MULTIPLY(qty, price)')).toBe(50)
  })

  it('evaluates DIVIDE', () => {
    const engine = new FormulaEngine({ total: 100, count: 4 })
    expect(engine.evaluate('DIVIDE(total, count)')).toBe(25)
  })

  it('evaluates DIVIDE with zero returns 0', () => {
    const engine = new FormulaEngine({ total: 100, count: 0 })
    expect(engine.evaluate('DIVIDE(total, count)')).toBe(0)
  })

  it('evaluates MIN', () => {
    const engine = new FormulaEngine({ a: 5, b: 3, c: 8 })
    expect(engine.evaluate('MIN(a, b, c)')).toBe(3)
  })

  it('evaluates MAX', () => {
    const engine = new FormulaEngine({ a: 5, b: 3, c: 8 })
    expect(engine.evaluate('MAX(a, b, c)')).toBe(8)
  })

  it('evaluates AVERAGE', () => {
    const engine = new FormulaEngine({ a: 10, b: 20, c: 30 })
    expect(engine.evaluate('AVERAGE(a, b, c)')).toBe(20)
  })

  it('evaluates ROUND', () => {
    const engine = new FormulaEngine({ price: 10.567 })
    expect(engine.evaluate('ROUND(price, 2)')).toBe(10.57)
  })

  it('evaluates FLOOR', () => {
    const engine = new FormulaEngine({ value: 3.7 })
    expect(engine.evaluate('FLOOR(value)')).toBe(3)
  })

  it('evaluates CEIL', () => {
    const engine = new FormulaEngine({ value: 3.2 })
    expect(engine.evaluate('CEIL(value)')).toBe(4)
  })

  it('evaluates ABS', () => {
    const engine = new FormulaEngine({ value: -5 })
    expect(engine.evaluate('ABS(value)')).toBe(5)
  })

  it('evaluates MOD', () => {
    const engine = new FormulaEngine({ a: 10, b: 3 })
    expect(engine.evaluate('MOD(a, b)')).toBe(1)
  })
})
```

**Step 2: Run tests to verify they fail**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: Multiple FAIL with "Unknown function"

**Step 3: Implement math functions**

Update `registerFunctions()` in `app/javascript/lib/formula_engine.js`:
```javascript
registerFunctions() {
  return {
    // Math functions
    SUM: (...args) => args.reduce((sum, val) => sum + (Number(val) || 0), 0),

    SUBTRACT: (a, b) => Number(a) - Number(b),

    MULTIPLY: (...args) => args.reduce((prod, val) => prod * (Number(val) || 0), 1),

    DIVIDE: (a, b) => {
      const divisor = Number(b)
      return divisor === 0 ? 0 : Number(a) / divisor
    },

    MIN: (...args) => Math.min(...args.map(Number)),

    MAX: (...args) => Math.max(...args.map(Number)),

    AVERAGE: (...args) => {
      const nums = args.map(Number)
      return nums.reduce((a, b) => a + b, 0) / nums.length
    },

    ROUND: (num, decimals = 0) => {
      const factor = Math.pow(10, decimals)
      return Math.round(Number(num) * factor) / factor
    },

    FLOOR: (num) => Math.floor(Number(num)),

    CEIL: (num) => Math.ceil(Number(num)),

    ABS: (num) => Math.abs(Number(num)),

    MOD: (a, b) => Number(a) % Number(b)
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/formula_engine.js spec/javascript/lib/formula_engine_spec.js
git commit -m "feat: add math functions to FormulaEngine"
```

---

### Task 7: Formula Engine - Conditional and String Functions

**Files:**
- Modify: `app/javascript/lib/formula_engine.js`
- Modify: `spec/javascript/lib/formula_engine_spec.js`

**Step 1: Write failing tests for conditional and string functions**

Add to `spec/javascript/lib/formula_engine_spec.js`:
```javascript
describe('conditional functions', () => {
  it('evaluates IF with true condition', () => {
    const engine = new FormulaEngine({ age: 25 })
    expect(engine.evaluate('IF(age >= 18, "Adult", "Minor")')).toBe('Adult')
  })

  it('evaluates IF with false condition', () => {
    const engine = new FormulaEngine({ age: 15 })
    expect(engine.evaluate('IF(age >= 18, "Adult", "Minor")')).toBe('Minor')
  })

  it('evaluates nested IF', () => {
    const engine = new FormulaEngine({ score: 85 })
    expect(engine.evaluate('IF(score >= 90, "A", IF(score >= 80, "B", "C"))')).toBe('B')
  })

  it('evaluates AND', () => {
    const engine = new FormulaEngine({ a: 5, b: 10 })
    expect(engine.evaluate('AND(a > 0, b > 0)')).toBe(true)
  })

  it('evaluates AND with false', () => {
    const engine = new FormulaEngine({ a: -1, b: 10 })
    expect(engine.evaluate('AND(a > 0, b > 0)')).toBe(false)
  })

  it('evaluates OR', () => {
    const engine = new FormulaEngine({ a: -1, b: 10 })
    expect(engine.evaluate('OR(a > 0, b > 0)')).toBe(true)
  })

  it('evaluates NOT', () => {
    const engine = new FormulaEngine({ active: false })
    expect(engine.evaluate('NOT(active)')).toBe(true)
  })

  it('evaluates SWITCH', () => {
    const engine = new FormulaEngine({ tier: 'gold' })
    expect(engine.evaluate('SWITCH(tier, "gold", 20, "silver", 10, 0)')).toBe(20)
  })

  it('evaluates SWITCH with default', () => {
    const engine = new FormulaEngine({ tier: 'bronze' })
    expect(engine.evaluate('SWITCH(tier, "gold", 20, "silver", 10, 0)')).toBe(0)
  })
})

describe('string functions', () => {
  it('evaluates CONCAT', () => {
    const engine = new FormulaEngine({ first: 'John', last: 'Doe' })
    expect(engine.evaluate('CONCAT(first, " ", last)')).toBe('John Doe')
  })

  it('evaluates UPPER', () => {
    const engine = new FormulaEngine({ name: 'john' })
    expect(engine.evaluate('UPPER(name)')).toBe('JOHN')
  })

  it('evaluates LOWER', () => {
    const engine = new FormulaEngine({ name: 'JOHN' })
    expect(engine.evaluate('LOWER(name)')).toBe('john')
  })

  it('evaluates TRIM', () => {
    const engine = new FormulaEngine({ text: '  hello  ' })
    expect(engine.evaluate('TRIM(text)')).toBe('hello')
  })

  it('evaluates LENGTH', () => {
    const engine = new FormulaEngine({ text: 'hello' })
    expect(engine.evaluate('LENGTH(text)')).toBe(5)
  })

  it('evaluates LEFT', () => {
    const engine = new FormulaEngine({ text: 'hello' })
    expect(engine.evaluate('LEFT(text, 2)')).toBe('he')
  })

  it('evaluates RIGHT', () => {
    const engine = new FormulaEngine({ text: 'hello' })
    expect(engine.evaluate('RIGHT(text, 2)')).toBe('lo')
  })
})
```

**Step 2: Run tests to verify they fail**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: Multiple FAIL

**Step 3: Implement conditional and string functions**

Add to `registerFunctions()` in `app/javascript/lib/formula_engine.js`:
```javascript
// Conditional functions
IF: (condition, thenValue, elseValue) => condition ? thenValue : elseValue,

AND: (...args) => args.every(Boolean),

OR: (...args) => args.some(Boolean),

NOT: (value) => !value,

SWITCH: (value, ...cases) => {
  for (let i = 0; i < cases.length - 1; i += 2) {
    if (value == cases[i]) {
      return cases[i + 1]
    }
  }
  // Return default (last argument if odd number of case args)
  return cases.length % 2 === 1 ? cases[cases.length - 1] : null
},

// String functions
CONCAT: (...args) => args.join(''),

UPPER: (str) => String(str ?? '').toUpperCase(),

LOWER: (str) => String(str ?? '').toLowerCase(),

TRIM: (str) => String(str ?? '').trim(),

LENGTH: (str) => String(str ?? '').length,

LEFT: (str, n) => String(str ?? '').substring(0, n),

RIGHT: (str, n) => {
  const s = String(str ?? '')
  return s.substring(s.length - n)
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/formula_engine.js spec/javascript/lib/formula_engine_spec.js
git commit -m "feat: add conditional and string functions to FormulaEngine"
```

---

### Task 8: Formula Engine - Date Functions

**Files:**
- Modify: `app/javascript/lib/formula_engine.js`
- Modify: `spec/javascript/lib/formula_engine_spec.js`

**Step 1: Write failing tests for date functions**

Add to `spec/javascript/lib/formula_engine_spec.js`:
```javascript
describe('date functions', () => {
  it('evaluates TODAY', () => {
    const engine = new FormulaEngine({})
    const result = engine.evaluate('TODAY()')
    const today = new Date()
    expect(result.getFullYear()).toBe(today.getFullYear())
    expect(result.getMonth()).toBe(today.getMonth())
    expect(result.getDate()).toBe(today.getDate())
  })

  it('evaluates NOW', () => {
    const engine = new FormulaEngine({})
    const before = new Date()
    const result = engine.evaluate('NOW()')
    const after = new Date()
    expect(result.getTime()).toBeGreaterThanOrEqual(before.getTime())
    expect(result.getTime()).toBeLessThanOrEqual(after.getTime())
  })

  it('evaluates YEAR', () => {
    const engine = new FormulaEngine({ date: '2024-06-15' })
    expect(engine.evaluate('YEAR(date)')).toBe(2024)
  })

  it('evaluates MONTH', () => {
    const engine = new FormulaEngine({ date: '2024-06-15' })
    expect(engine.evaluate('MONTH(date)')).toBe(6)
  })

  it('evaluates DAY', () => {
    const engine = new FormulaEngine({ date: '2024-06-15' })
    expect(engine.evaluate('DAY(date)')).toBe(15)
  })

  it('evaluates DATE_DIFF in days', () => {
    const engine = new FormulaEngine({
      start: '2024-01-01',
      end: '2024-01-10'
    })
    expect(engine.evaluate('DATE_DIFF(end, start, "days")')).toBe(9)
  })

  it('evaluates DATE_ADD', () => {
    const engine = new FormulaEngine({ start: '2024-01-01' })
    const result = engine.evaluate('DATE_ADD(start, 7, "days")')
    expect(result.toISOString().slice(0, 10)).toBe('2024-01-08')
  })
})
```

**Step 2: Run tests to verify they fail**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: Multiple FAIL

**Step 3: Implement date functions**

Add to `registerFunctions()` in `app/javascript/lib/formula_engine.js`:
```javascript
// Date functions
TODAY: () => {
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate())
},

NOW: () => new Date(),

YEAR: (date) => new Date(date).getFullYear(),

MONTH: (date) => new Date(date).getMonth() + 1,

DAY: (date) => new Date(date).getDate(),

DATE_DIFF: (date1, date2, unit = 'days') => {
  const d1 = new Date(date1)
  const d2 = new Date(date2)
  const diffMs = d1 - d2

  switch (unit) {
    case 'days':
      return Math.floor(diffMs / (1000 * 60 * 60 * 24))
    case 'hours':
      return Math.floor(diffMs / (1000 * 60 * 60))
    case 'minutes':
      return Math.floor(diffMs / (1000 * 60))
    case 'seconds':
      return Math.floor(diffMs / 1000)
    case 'months':
      return (d1.getFullYear() - d2.getFullYear()) * 12 + (d1.getMonth() - d2.getMonth())
    case 'years':
      return d1.getFullYear() - d2.getFullYear()
    default:
      return Math.floor(diffMs / (1000 * 60 * 60 * 24))
  }
},

DATE_ADD: (date, amount, unit = 'days') => {
  const d = new Date(date)

  switch (unit) {
    case 'days':
      d.setDate(d.getDate() + amount)
      break
    case 'months':
      d.setMonth(d.getMonth() + amount)
      break
    case 'years':
      d.setFullYear(d.getFullYear() + amount)
      break
    case 'hours':
      d.setHours(d.getHours() + amount)
      break
    case 'minutes':
      d.setMinutes(d.getMinutes() + amount)
      break
  }

  return d
}
```

**Step 4: Run tests to verify they pass**

Run: `yarn jest spec/javascript/lib/formula_engine_spec.js`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/javascript/lib/formula_engine.js spec/javascript/lib/formula_engine_spec.js
git commit -m "feat: add date functions to FormulaEngine"
```

---

## Phase 2: Model & Migration (Ruby)

### Task 9: Page Model - Migration Logic

**Files:**
- Modify: `app/models/page.rb`
- Modify: `spec/models/page_spec.rb`

**Step 1: Write failing test for migration**

Add to `spec/models/page_spec.rb`:
```ruby
RSpec.describe Page do
  describe '#configuration_json migration' do
    context 'with legacy field-level conditions' do
      let(:legacy_config) do
        {
          'pages' => [{
            'id' => 'page_1',
            'name' => 'Page 1',
            'fields' => [{
              'id' => 'address_field',
              'label' => 'Address',
              'property_type' => 'string',
              'conditions' => [
                { 'field_id' => 'needs_shipping', 'operator' => 'equals', 'value' => 'yes' }
              ]
            }]
          }],
          'metadata' => {}
        }
      end

      let(:page) { create(:page, configuration: legacy_config.to_json) }

      it 'migrates field conditions to rules array' do
        config = page.configuration_json
        expect(config['rules']).to be_present
        expect(config['rules'].length).to eq(1)
      end

      it 'creates rule with show_field action' do
        config = page.configuration_json
        rule = config['rules'].first
        expect(rule['actions']).to include(
          hash_including('type' => 'show_field', 'target_id' => 'address_field')
        )
      end

      it 'converts conditions to nested group format' do
        config = page.configuration_json
        rule = config['rules'].first
        expect(rule['conditions']['logic']).to eq('all')
        expect(rule['conditions']['groups']).to be_present
      end

      it 'removes conditions from field' do
        config = page.configuration_json
        field = config.dig('pages', 0, 'fields', 0)
        expect(field['conditions']).to be_nil
      end

      it 'initializes empty calculations array' do
        config = page.configuration_json
        expect(config['calculations']).to eq([])
      end
    end

    context 'with already migrated config' do
      let(:modern_config) do
        {
          'pages' => [{ 'id' => 'page_1', 'fields' => [] }],
          'metadata' => {},
          'rules' => [{ 'id' => 'rule_1', 'enabled' => true }],
          'calculations' => []
        }
      end

      let(:page) { create(:page, configuration: modern_config.to_json) }

      it 'does not duplicate rules' do
        config = page.configuration_json
        expect(config['rules'].length).to eq(1)
      end
    end

    context 'with no conditions' do
      let(:clean_config) do
        {
          'pages' => [{ 'id' => 'page_1', 'fields' => [{ 'id' => 'f1' }] }],
          'metadata' => {}
        }
      end

      let(:page) { create(:page, configuration: clean_config.to_json) }

      it 'adds empty rules and calculations arrays' do
        config = page.configuration_json
        expect(config['rules']).to eq([])
        expect(config['calculations']).to eq([])
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/page_spec.rb -e "migration"`
Expected: FAIL

**Step 3: Implement migration logic**

Add to `app/models/page.rb`:
```ruby
# Replace or modify configuration_json method
def configuration_json
  return nil if configuration.blank?

  config = JSON.parse(configuration)
  migrate_to_rules_format(config)
end

private

def migrate_to_rules_format(config)
  # Skip if already migrated or has rules
  return config if config['rules'].present?

  rules = []

  # Find all fields with conditions across all pages
  config['pages']&.each do |page|
    page['fields']&.each do |field|
      next if field['conditions'].blank?

      # Create rule from field conditions
      rules << {
        'id' => "migrated_#{field['id']}_#{SecureRandom.hex(4)}",
        'name' => "Show #{field['label'] || field['id']}",
        'enabled' => true,
        'conditions' => migrate_conditions_format(field['conditions']),
        'actions' => [{ 'type' => 'show_field', 'target_id' => field['id'] }]
      }

      # Remove conditions from field
      field.delete('conditions')
    end
  end

  config['rules'] = rules
  config['calculations'] ||= []
  config
end

def migrate_conditions_format(old_conditions)
  return { 'logic' => 'all', 'groups' => [] } if old_conditions.blank?

  # Determine if any condition used 'or' logic
  has_or = old_conditions.any? { |c| c['logic'] == 'or' }

  {
    'logic' => 'all',
    'groups' => [{
      'logic' => has_or ? 'any' : 'all',
      'items' => old_conditions.map { |c| c.except('logic') }
    }]
  }
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/page_spec.rb -e "migration"`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/models/page.rb spec/models/page_spec.rb
git commit -m "feat: add automatic migration from field conditions to rules"
```

---

### Task 10: Page Model - Rules Validation

**Files:**
- Modify: `app/models/page.rb`
- Modify: `spec/models/page_spec.rb`

**Step 1: Write failing tests for validation**

Add to `spec/models/page_spec.rb`:
```ruby
describe 'rules validation' do
  it 'validates rule has required id' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [{ 'enabled' => true, 'conditions' => {}, 'actions' => [] }]
    }
    page = build(:page, configuration: config.to_json)

    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to include('id')
  end

  it 'validates rule has conditions' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [{ 'id' => 'r1', 'enabled' => true, 'actions' => [] }]
    }
    page = build(:page, configuration: config.to_json)

    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to include('conditions')
  end

  it 'validates rule has actions' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [{ 'id' => 'r1', 'enabled' => true, 'conditions' => {} }]
    }
    page = build(:page, configuration: config.to_json)

    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to include('actions')
  end

  it 'accepts valid rule structure' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [{
        'id' => 'r1',
        'enabled' => true,
        'conditions' => { 'logic' => 'all', 'groups' => [] },
        'actions' => [{ 'type' => 'show_field', 'target_id' => 'f1' }]
      }],
      'calculations' => []
    }
    page = build(:page, configuration: config.to_json)

    expect(page).to be_valid
  end
end

describe 'calculations validation' do
  it 'validates calculation has target_field_id' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [],
      'calculations' => [{ 'id' => 'c1', 'formula' => 'a + b' }]
    }
    page = build(:page, configuration: config.to_json)

    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to include('target_field_id')
  end

  it 'validates calculation has formula' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [],
      'calculations' => [{ 'id' => 'c1', 'target_field_id' => 'total' }]
    }
    page = build(:page, configuration: config.to_json)

    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to include('formula')
  end

  it 'accepts valid calculation structure' do
    config = {
      'pages' => [], 'metadata' => {},
      'rules' => [],
      'calculations' => [{
        'id' => 'c1',
        'target_field_id' => 'total',
        'formula' => 'price * quantity'
      }]
    }
    page = build(:page, configuration: config.to_json)

    expect(page).to be_valid
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/page_spec.rb -e "validation"`
Expected: Multiple FAIL

**Step 3: Implement validation**

Add to `app/models/page.rb`:
```ruby
def configuration_must_have_required_structure
  return if configuration.blank? || !configuration_json

  validate_required_keys
  validate_fields_structure
  validate_metadata_structure
  validate_rules_structure
  validate_calculations_structure
end

def validate_rules_structure
  rules = configuration_json['rules']
  return unless rules.is_a?(Array)

  rules.each_with_index do |rule, idx|
    errors.add(:configuration, "Rule #{idx + 1} missing id") if rule['id'].blank?
    errors.add(:configuration, "Rule #{idx + 1} missing conditions") unless rule.key?('conditions')
    errors.add(:configuration, "Rule #{idx + 1} missing actions") unless rule.key?('actions')
  end
end

def validate_calculations_structure
  calculations = configuration_json['calculations']
  return unless calculations.is_a?(Array)

  calculations.each_with_index do |calc, idx|
    errors.add(:configuration, "Calculation #{idx + 1} missing target_field_id") if calc['target_field_id'].blank?
    errors.add(:configuration, "Calculation #{idx + 1} missing formula") if calc['formula'].blank?
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/page_spec.rb -e "validation"`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/models/page.rb spec/models/page_spec.rb
git commit -m "feat: add rules and calculations validation to Page model"
```

---

## Phase 3: Runtime Controller (JavaScript)

### Task 11: Condition Runtime Controller - Setup

**Files:**
- Create: `app/javascript/controllers/condition_runtime_controller.js`

**Step 1: Create controller skeleton**

Create `app/javascript/controllers/condition_runtime_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"
import { ConditionEvaluator } from "../lib/condition_evaluator"
import { FormulaEngine } from "../lib/formula_engine"

/**
 * Condition Runtime Controller
 *
 * Evaluates conditional logic and calculations at form runtime.
 * Attached to the form wrapper element.
 */
export default class extends Controller {
  static values = {
    rules: { type: Array, default: [] },
    calculations: { type: Array, default: [] }
  }

  connect() {
    this.fieldElements = new Map()
    this.cacheFieldElements()
    this.bindFieldListeners()
    this.evaluateAll()
    console.log('ConditionRuntime connected', {
      rules: this.rulesValue.length,
      calculations: this.calculationsValue.length
    })
  }

  disconnect() {
    this.unbindFieldListeners()
  }

  cacheFieldElements() {
    this.element.querySelectorAll('[data-field-id]').forEach(el => {
      this.fieldElements.set(el.dataset.fieldId, el)
    })
  }

  bindFieldListeners() {
    this.fieldChangeHandler = this.debounce((event) => {
      this.evaluateAll()
    }, 100)

    this.element.addEventListener('input', this.fieldChangeHandler)
    this.element.addEventListener('change', this.fieldChangeHandler)
  }

  unbindFieldListeners() {
    this.element.removeEventListener('input', this.fieldChangeHandler)
    this.element.removeEventListener('change', this.fieldChangeHandler)
  }

  evaluateAll() {
    const values = this.collectFieldValues()
    this.applyRules(values)
    this.applyCalculations(values)
  }

  collectFieldValues() {
    const values = {}

    this.fieldElements.forEach((wrapper, fieldId) => {
      const input = wrapper.querySelector('input, select, textarea')
      if (input) {
        if (input.type === 'checkbox') {
          values[fieldId] = input.checked
        } else if (input.type === 'radio') {
          const checked = wrapper.querySelector('input[type="radio"]:checked')
          values[fieldId] = checked?.value ?? null
        } else {
          values[fieldId] = input.value
        }
      }
    })

    return values
  }

  applyRules(values) {
    const evaluator = new ConditionEvaluator(values)

    this.rulesValue.forEach(rule => {
      if (!rule.enabled) return

      const matched = evaluator.evaluate(rule.conditions)

      rule.actions.forEach(action => {
        this.executeAction(action, matched)
      })
    })
  }

  executeAction(action, shouldApply) {
    const wrapper = this.fieldElements.get(action.target_id)
    if (!wrapper) return

    switch (action.type) {
      case 'show_field':
        wrapper.classList.toggle('hidden', !shouldApply)
        wrapper.setAttribute('aria-hidden', !shouldApply)
        break

      case 'hide_field':
        wrapper.classList.toggle('hidden', shouldApply)
        wrapper.setAttribute('aria-hidden', shouldApply)
        break

      case 'enable_field': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input) {
          input.disabled = !shouldApply
          wrapper.classList.toggle('field-disabled', !shouldApply)
        }
        break
      }

      case 'disable_field': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input) {
          input.disabled = shouldApply
          wrapper.classList.toggle('field-disabled', shouldApply)
        }
        break
      }

      case 'set_required': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input && shouldApply) {
          input.required = action.value
          input.setAttribute('aria-required', action.value)
        }
        break
      }

      case 'set_value': {
        const input = wrapper.querySelector('input, select, textarea')
        if (input && shouldApply) {
          input.value = action.value
          input.dispatchEvent(new Event('change', { bubbles: true }))
        }
        break
      }
    }
  }

  applyCalculations(values) {
    const engine = new FormulaEngine(values)

    this.calculationsValue.forEach(calc => {
      const result = engine.evaluate(calc.formula)
      const wrapper = this.fieldElements.get(calc.target_field_id)

      if (wrapper) {
        const input = wrapper.querySelector('input, select, textarea')
        if (input && result !== null) {
          let displayValue = result

          if (calc.format?.type === 'currency') {
            displayValue = Number(result).toFixed(calc.format.decimals ?? 2)
          } else if (calc.format?.type === 'number' && calc.format.decimals) {
            displayValue = Number(result).toFixed(calc.format.decimals)
          }

          input.value = displayValue
        }
      }
    })
  }

  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
```

**Step 2: Register controller**

Ensure the controller is auto-registered via esbuild/importmap. Check `app/javascript/controllers/index.js`:

```javascript
// If using manual registration, add:
import ConditionRuntimeController from "./condition_runtime_controller"
application.register("condition-runtime", ConditionRuntimeController)
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/condition_runtime_controller.js
git commit -m "feat: add condition_runtime_controller for form runtime evaluation"
```

---

### Task 12: PageContentGenerator - Runtime Integration

**Files:**
- Modify: `app/services/page_content_generator.rb`
- Modify: `spec/services/page_content_generator_spec.rb`

**Step 1: Write failing test**

Add to `spec/services/page_content_generator_spec.rb`:
```ruby
describe 'runtime controller integration' do
  let(:config) do
    {
      'pages' => [{
        'id' => 'page_1',
        'fields' => [{ 'id' => 'f1', 'property_type' => 'string', 'label' => 'Name' }]
      }],
      'metadata' => {},
      'rules' => [{
        'id' => 'r1',
        'enabled' => true,
        'conditions' => { 'logic' => 'all', 'groups' => [] },
        'actions' => [{ 'type' => 'show_field', 'target_id' => 'f2' }]
      }],
      'calculations' => [{
        'id' => 'c1',
        'target_field_id' => 'total',
        'formula' => 'price * qty'
      }]
    }
  end

  let(:page) { create(:page, configuration: config.to_json) }
  subject { described_class.new(page).generate }

  it 'wraps content with condition-runtime controller' do
    expect(subject).to include('data-controller="condition-runtime"')
  end

  it 'includes rules as JSON data attribute' do
    expect(subject).to include('data-condition-runtime-rules-value')
  end

  it 'includes calculations as JSON data attribute' do
    expect(subject).to include('data-condition-runtime-calculations-value')
  end

  it 'adds data-field-id to field wrappers' do
    expect(subject).to include('data-field-id="f1"')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/page_content_generator_spec.rb -e "runtime"`
Expected: FAIL

**Step 3: Implement runtime integration**

Update `app/services/page_content_generator.rb`:
```ruby
def generate
  pages_config = page.configuration_json['pages'] || []
  settings = page.configuration_json['settings'] || {}

  content = if pages_config.size > 1
              generate_wizard(pages_config, settings)
            else
              generate_single_page(pages_config.first, settings)
            end

  wrap_with_runtime_controller(content)
end

private

def wrap_with_runtime_controller(content)
  rules = page.configuration_json['rules'] || []
  calculations = page.configuration_json['calculations'] || []

  rules_json = ERB::Util.html_escape(rules.to_json)
  calcs_json = ERB::Util.html_escape(calculations.to_json)

  <<~HTML
    <div data-controller="condition-runtime"
         data-condition-runtime-rules-value="#{rules_json}"
         data-condition-runtime-calculations-value="#{calcs_json}">
      #{content}
    </div>
  HTML
end

# Update field wrapper generation to include data-field-id
def generate_field_wrapper(field, content)
  width_class = field_width_class(field['width'])
  <<~HTML
    <div class="#{width_class}" data-field-id="#{field['id']}">
      #{content}
    </div>
  HTML
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/page_content_generator_spec.rb -e "runtime"`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/services/page_content_generator.rb spec/services/page_content_generator_spec.rb
git commit -m "feat: integrate condition-runtime controller into generated forms"
```

---

## Phase 4: UI Components

### Task 13: RulesPanelComponent

**Files:**
- Create: `app/components/page_builder/rules_panel_component.rb`
- Create: `app/components/page_builder/rules_panel_component.html.erb`
- Create: `spec/components/page_builder/rules_panel_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/page_builder/rules_panel_component_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::RulesPanelComponent, type: :component do
  let(:rules) do
    [
      {
        'id' => 'rule_1',
        'name' => 'Show shipping address',
        'enabled' => true,
        'conditions' => { 'logic' => 'all', 'groups' => [] },
        'actions' => [{ 'type' => 'show_field', 'target_id' => 'address' }]
      },
      {
        'id' => 'rule_2',
        'name' => 'Disabled rule',
        'enabled' => false,
        'conditions' => {},
        'actions' => []
      }
    ]
  end

  subject { render_inline(described_class.new(rules: rules)) }

  it 'renders the rules panel header' do
    expect(subject).to have_css('[data-rules-panel]')
    expect(subject).to have_text('Conditional Rules')
  end

  it 'renders each rule' do
    expect(subject).to have_css('[data-rule-id="rule_1"]')
    expect(subject).to have_css('[data-rule-id="rule_2"]')
  end

  it 'shows rule names' do
    expect(subject).to have_text('Show shipping address')
    expect(subject).to have_text('Disabled rule')
  end

  it 'shows enabled indicator for active rules' do
    expect(subject).to have_css('[data-rule-id="rule_1"] .rule-enabled')
  end

  it 'shows disabled indicator for inactive rules' do
    expect(subject).to have_css('[data-rule-id="rule_2"] .rule-disabled')
  end

  it 'renders add rule button' do
    expect(subject).to have_css('[data-action*="openRuleEditor"]')
  end

  it 'renders edit button for each rule' do
    expect(subject).to have_css('[data-action*="editRule"]', count: 2)
  end

  it 'renders delete button for each rule' do
    expect(subject).to have_css('[data-action*="deleteRule"]', count: 2)
  end

  context 'with no rules' do
    let(:rules) { [] }

    it 'shows empty state message' do
      expect(subject).to have_text('No rules defined')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/rules_panel_component_spec.rb`
Expected: FAIL with "uninitialized constant"

**Step 3: Implement component**

Create `app/components/page_builder/rules_panel_component.rb`:
```ruby
# frozen_string_literal: true

module PageBuilder
  class RulesPanelComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    def initialize(rules: [])
      @rules = rules || []
    end

    private

    attr_reader :rules

    def empty?
      rules.empty?
    end
  end
end
```

Create `app/components/page_builder/rules_panel_component.html.erb`:
```erb
<div data-rules-panel class="space-y-3">
  <div class="flex items-center justify-between">
    <h3 class="text-sm font-medium text-gray-700">Conditional Rules</h3>
    <button type="button"
            class="p-1 text-gray-400 hover:text-indigo-600 transition-colors"
            data-action="click->page-builder#openRuleEditor"
            title="Add rule">
      <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
      </svg>
    </button>
  </div>

  <% if empty? %>
    <div class="text-sm text-gray-500 text-center py-4">
      No rules defined
    </div>
  <% else %>
    <div class="space-y-2">
      <% rules.each do |rule| %>
        <div data-rule-id="<%= rule['id'] %>"
             class="p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 transition-colors">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="<%= rule['enabled'] ? 'rule-enabled text-green-500' : 'rule-disabled text-gray-400' %>">
                <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 8 8">
                  <circle cx="4" cy="4" r="4" />
                </svg>
              </span>
              <span class="text-sm font-medium text-gray-700 truncate max-w-[150px]">
                <%= rule['name'] || 'Unnamed rule' %>
              </span>
            </div>
            <div class="flex items-center gap-1">
              <button type="button"
                      class="p-1 text-gray-400 hover:text-indigo-600 transition-colors"
                      data-action="click->page-builder#editRule"
                      data-rule-id="<%= rule['id'] %>"
                      title="Edit rule">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
              </button>
              <button type="button"
                      class="p-1 text-gray-400 hover:text-red-500 transition-colors"
                      data-action="click->page-builder#deleteRule"
                      data-rule-id="<%= rule['id'] %>"
                      title="Delete rule">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            </div>
          </div>
          <div class="mt-1 text-xs text-gray-500">
            <%= pluralize(rule['actions']&.length || 0, 'action') %>
          </div>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/rules_panel_component_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/rules_panel_component.rb \
        app/components/page_builder/rules_panel_component.html.erb \
        spec/components/page_builder/rules_panel_component_spec.rb
git commit -m "feat: add RulesPanelComponent for displaying conditional rules"
```

---

### Task 14: CalculationsPanelComponent

**Files:**
- Create: `app/components/page_builder/calculations_panel_component.rb`
- Create: `app/components/page_builder/calculations_panel_component.html.erb`
- Create: `spec/components/page_builder/calculations_panel_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/page_builder/calculations_panel_component_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::CalculationsPanelComponent, type: :component do
  let(:calculations) do
    [
      {
        'id' => 'calc_1',
        'target_field_id' => 'total_price',
        'formula' => 'quantity * unit_price'
      },
      {
        'id' => 'calc_2',
        'target_field_id' => 'grand_total',
        'formula' => 'SUM(total_price, tax, shipping)'
      }
    ]
  end
  let(:fields) do
    [
      { 'id' => 'total_price', 'label' => 'Total Price' },
      { 'id' => 'grand_total', 'label' => 'Grand Total' }
    ]
  end

  subject { render_inline(described_class.new(calculations: calculations, fields: fields)) }

  it 'renders the calculations panel' do
    expect(subject).to have_css('[data-calculations-panel]')
    expect(subject).to have_text('Calculated Fields')
  end

  it 'renders each calculation' do
    expect(subject).to have_css('[data-calculation-id="calc_1"]')
    expect(subject).to have_css('[data-calculation-id="calc_2"]')
  end

  it 'shows target field labels' do
    expect(subject).to have_text('Total Price')
    expect(subject).to have_text('Grand Total')
  end

  it 'shows formula preview' do
    expect(subject).to have_text('quantity * unit_price')
  end

  it 'renders add calculation button' do
    expect(subject).to have_css('[data-action*="openFormulaEditor"]')
  end

  context 'with no calculations' do
    let(:calculations) { [] }

    it 'shows empty state' do
      expect(subject).to have_text('No calculated fields')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/calculations_panel_component_spec.rb`
Expected: FAIL

**Step 3: Implement component**

Create `app/components/page_builder/calculations_panel_component.rb`:
```ruby
# frozen_string_literal: true

module PageBuilder
  class CalculationsPanelComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    def initialize(calculations: [], fields: [])
      @calculations = calculations || []
      @fields = fields || []
    end

    private

    attr_reader :calculations, :fields

    def empty?
      calculations.empty?
    end

    def field_label(field_id)
      field = fields.find { |f| f['id'] == field_id }
      field&.dig('label') || field_id
    end

    def truncate_formula(formula, length: 30)
      return '' if formula.blank?

      formula.length > length ? "#{formula[0...length]}..." : formula
    end
  end
end
```

Create `app/components/page_builder/calculations_panel_component.html.erb`:
```erb
<div data-calculations-panel class="space-y-3">
  <div class="flex items-center justify-between">
    <h3 class="text-sm font-medium text-gray-700">Calculated Fields</h3>
    <button type="button"
            class="p-1 text-gray-400 hover:text-indigo-600 transition-colors"
            data-action="click->page-builder#openFormulaEditor"
            title="Add calculation">
      <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
      </svg>
    </button>
  </div>

  <% if empty? %>
    <div class="text-sm text-gray-500 text-center py-4">
      No calculated fields
    </div>
  <% else %>
    <div class="space-y-2">
      <% calculations.each do |calc| %>
        <div data-calculation-id="<%= calc['id'] %>"
             class="p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 transition-colors">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-gray-700">
              <%= field_label(calc['target_field_id']) %>
            </span>
            <div class="flex items-center gap-1">
              <button type="button"
                      class="p-1 text-gray-400 hover:text-indigo-600 transition-colors"
                      data-action="click->page-builder#editCalculation"
                      data-calculation-id="<%= calc['id'] %>"
                      title="Edit calculation">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
              </button>
              <button type="button"
                      class="p-1 text-gray-400 hover:text-red-500 transition-colors"
                      data-action="click->page-builder#deleteCalculation"
                      data-calculation-id="<%= calc['id'] %>"
                      title="Delete calculation">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            </div>
          </div>
          <div class="mt-1 text-xs text-gray-500 font-mono">
            = <%= truncate_formula(calc['formula']) %>
          </div>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/calculations_panel_component_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/calculations_panel_component.rb \
        app/components/page_builder/calculations_panel_component.html.erb \
        spec/components/page_builder/calculations_panel_component_spec.rb
git commit -m "feat: add CalculationsPanelComponent for displaying calculated fields"
```

---

### Task 15: RuleEditorComponent

**Files:**
- Create: `app/components/page_builder/rule_editor_component.rb`
- Create: `app/components/page_builder/rule_editor_component.html.erb`
- Create: `spec/components/page_builder/rule_editor_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/page_builder/rule_editor_component_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::RuleEditorComponent, type: :component do
  let(:rule) do
    {
      'id' => 'rule_1',
      'name' => 'Test Rule',
      'enabled' => true,
      'conditions' => { 'logic' => 'all', 'groups' => [] },
      'actions' => []
    }
  end
  let(:fields) { [{ 'id' => 'f1', 'label' => 'Field 1' }] }
  let(:pages) { [{ 'id' => 'p1', 'name' => 'Page 1' }] }

  subject { render_inline(described_class.new(rule: rule, fields: fields, pages: pages)) }

  it 'renders the rule editor modal' do
    expect(subject).to have_css('[data-rule-editor-modal]')
  end

  it 'renders rule name input' do
    expect(subject).to have_field('rule_name')
  end

  it 'pre-fills rule name' do
    expect(subject).to have_field('rule_name', with: 'Test Rule')
  end

  it 'renders conditions section' do
    expect(subject).to have_css('[data-conditions-section]')
  end

  it 'renders actions section' do
    expect(subject).to have_css('[data-actions-section]')
  end

  it 'includes all operators' do
    described_class::OPERATORS.each do |op|
      expect(subject.to_html).to include(op[:label])
    end
  end

  it 'includes all action types' do
    described_class::ACTION_TYPES.each do |at|
      expect(subject.to_html).to include(at[:label])
    end
  end

  it 'renders save and cancel buttons' do
    expect(subject).to have_button('Save Rule')
    expect(subject).to have_button('Cancel')
  end

  context 'with new rule' do
    let(:rule) { nil }

    it 'renders with empty name' do
      expect(subject).to have_field('rule_name', with: '')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/rule_editor_component_spec.rb`
Expected: FAIL

**Step 3: Implement component**

Create `app/components/page_builder/rule_editor_component.rb`:
```ruby
# frozen_string_literal: true

module PageBuilder
  class RuleEditorComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    OPERATORS = [
      { value: 'equals', label: 'Equals' },
      { value: 'not_equals', label: 'Not equals' },
      { value: 'contains', label: 'Contains' },
      { value: 'not_contains', label: 'Does not contain' },
      { value: 'starts_with', label: 'Starts with' },
      { value: 'ends_with', label: 'Ends with' },
      { value: 'greater_than', label: 'Greater than' },
      { value: 'less_than', label: 'Less than' },
      { value: 'greater_or_equal', label: 'Greater or equal' },
      { value: 'less_or_equal', label: 'Less or equal' },
      { value: 'between', label: 'Between' },
      { value: 'is_empty', label: 'Is empty' },
      { value: 'is_not_empty', label: 'Is not empty' },
      { value: 'is_selected', label: 'Is selected' },
      { value: 'is_not_selected', label: 'Is not selected' },
      { value: 'matches_regex', label: 'Matches pattern' }
    ].freeze

    ACTION_TYPES = [
      { value: 'show_field', label: 'Show field', target: 'field' },
      { value: 'hide_field', label: 'Hide field', target: 'field' },
      { value: 'show_page', label: 'Show page', target: 'page' },
      { value: 'hide_page', label: 'Hide page', target: 'page' },
      { value: 'skip_to_page', label: 'Skip to page', target: 'page' },
      { value: 'enable_field', label: 'Enable field', target: 'field' },
      { value: 'disable_field', label: 'Disable field', target: 'field' },
      { value: 'set_required', label: 'Set required', target: 'field', has_value: true },
      { value: 'set_value', label: 'Set value', target: 'field', has_value: true }
    ].freeze

    def initialize(rule: nil, fields: [], pages: [])
      @rule = rule || default_rule
      @fields = fields || []
      @pages = pages || []
    end

    def operators
      OPERATORS
    end

    def action_types
      ACTION_TYPES
    end

    private

    attr_reader :rule, :fields, :pages

    def default_rule
      {
        'id' => nil,
        'name' => '',
        'enabled' => true,
        'conditions' => { 'logic' => 'all', 'groups' => [] },
        'actions' => []
      }
    end

    def rule_name
      rule['name'] || ''
    end

    def rule_id
      rule['id']
    end

    def conditions
      rule['conditions'] || { 'logic' => 'all', 'groups' => [] }
    end

    def actions
      rule['actions'] || []
    end

    def new_rule?
      rule['id'].nil?
    end
  end
end
```

Create `app/components/page_builder/rule_editor_component.html.erb`:
```erb
<div data-rule-editor-modal
     data-rule-id="<%= rule_id %>"
     class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
  <div class="bg-white rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-hidden flex flex-col">
    <%# Header %>
    <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-gray-900">
        <%= new_rule? ? 'New Rule' : 'Edit Rule' %>
      </h2>
      <button type="button"
              class="p-2 text-gray-400 hover:text-gray-600 transition-colors"
              data-action="click->page-builder#closeRuleEditor">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>

    <%# Body %>
    <div class="flex-1 overflow-y-auto p-6 space-y-6">
      <%# Rule Name %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Rule Name</label>
        <input type="text"
               name="rule_name"
               value="<%= rule_name %>"
               class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
               placeholder="e.g., Show shipping address"
               data-page-builder-target="ruleNameInput">
      </div>

      <%# Conditions Section %>
      <div data-conditions-section>
        <div class="flex items-center justify-between mb-3">
          <label class="block text-sm font-medium text-gray-700">When these conditions are met</label>
          <select class="text-sm border border-gray-200 rounded px-2 py-1"
                  data-page-builder-target="conditionsLogic">
            <option value="all" <%= 'selected' if conditions['logic'] == 'all' %>>All (AND)</option>
            <option value="any" <%= 'selected' if conditions['logic'] == 'any' %>>Any (OR)</option>
          </select>
        </div>

        <div data-page-builder-target="conditionGroups" class="space-y-3">
          <%# Condition groups rendered by JS %>
        </div>

        <button type="button"
                class="mt-3 w-full px-3 py-2 text-sm text-gray-600 border border-dashed border-gray-300 rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
                data-action="click->page-builder#addConditionGroup">
          + Add Condition Group
        </button>
      </div>

      <%# Actions Section %>
      <div data-actions-section>
        <label class="block text-sm font-medium text-gray-700 mb-3">Then do these actions</label>

        <div data-page-builder-target="ruleActions" class="space-y-3">
          <%# Actions rendered by JS %>
        </div>

        <button type="button"
                class="mt-3 w-full px-3 py-2 text-sm text-gray-600 border border-dashed border-gray-300 rounded-lg hover:border-indigo-400 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
                data-action="click->page-builder#addAction">
          + Add Action
        </button>
      </div>

      <%# Hidden data for JS %>
      <template data-operators>
        <%= operators.to_json %>
      </template>
      <template data-action-types>
        <%= action_types.to_json %>
      </template>
      <template data-fields>
        <%= fields.to_json %>
      </template>
      <template data-pages>
        <%= pages.to_json %>
      </template>
    </div>

    <%# Footer %>
    <div class="px-6 py-4 border-t border-gray-200 flex justify-end gap-3">
      <button type="button"
              class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
              data-action="click->page-builder#closeRuleEditor">
        Cancel
      </button>
      <button type="button"
              class="px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 transition-colors"
              data-action="click->page-builder#saveRule">
        Save Rule
      </button>
    </div>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/rule_editor_component_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/rule_editor_component.rb \
        app/components/page_builder/rule_editor_component.html.erb \
        spec/components/page_builder/rule_editor_component_spec.rb
git commit -m "feat: add RuleEditorComponent modal for editing conditional rules"
```

---

### Task 16: FormulaEditorComponent

**Files:**
- Create: `app/components/page_builder/formula_editor_component.rb`
- Create: `app/components/page_builder/formula_editor_component.html.erb`
- Create: `spec/components/page_builder/formula_editor_component_spec.rb`

**Step 1: Write failing test**

Create `spec/components/page_builder/formula_editor_component_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::FormulaEditorComponent, type: :component do
  let(:calculation) do
    {
      'id' => 'calc_1',
      'target_field_id' => 'total',
      'formula' => 'price * quantity'
    }
  end
  let(:fields) do
    [
      { 'id' => 'price', 'label' => 'Price', 'property_type' => 'number' },
      { 'id' => 'quantity', 'label' => 'Quantity', 'property_type' => 'number' },
      { 'id' => 'total', 'label' => 'Total', 'property_type' => 'number' }
    ]
  end

  subject { render_inline(described_class.new(calculation: calculation, fields: fields)) }

  it 'renders the formula editor modal' do
    expect(subject).to have_css('[data-formula-editor-modal]')
  end

  it 'renders target field selector' do
    expect(subject).to have_select('target_field')
  end

  it 'renders formula textarea' do
    expect(subject).to have_css('textarea[name="formula"]')
  end

  it 'pre-fills formula' do
    expect(subject).to have_css('textarea', text: 'price * quantity')
  end

  it 'renders field reference buttons' do
    expect(subject).to have_button('price')
    expect(subject).to have_button('quantity')
  end

  it 'renders function categories' do
    expect(subject).to have_text('Math')
    expect(subject).to have_text('Logic')
    expect(subject).to have_text('Text')
    expect(subject).to have_text('Date')
  end

  it 'renders preview area' do
    expect(subject).to have_css('[data-formula-preview]')
  end

  it 'renders save and cancel buttons' do
    expect(subject).to have_button('Save')
    expect(subject).to have_button('Cancel')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/page_builder/formula_editor_component_spec.rb`
Expected: FAIL

**Step 3: Implement component**

Create `app/components/page_builder/formula_editor_component.rb`:
```ruby
# frozen_string_literal: true

module PageBuilder
  class FormulaEditorComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    FUNCTIONS = {
      'Math' => %w[SUM SUBTRACT MULTIPLY DIVIDE MIN MAX AVERAGE ROUND FLOOR CEIL ABS MOD],
      'Logic' => %w[IF AND OR NOT SWITCH],
      'Text' => %w[CONCAT UPPER LOWER TRIM LENGTH LEFT RIGHT],
      'Date' => %w[TODAY NOW YEAR MONTH DAY DATE_DIFF DATE_ADD]
    }.freeze

    def initialize(calculation: nil, fields: [])
      @calculation = calculation || default_calculation
      @fields = fields || []
    end

    def functions
      FUNCTIONS
    end

    private

    attr_reader :calculation, :fields

    def default_calculation
      {
        'id' => nil,
        'target_field_id' => '',
        'formula' => ''
      }
    end

    def calculation_id
      calculation['id']
    end

    def target_field_id
      calculation['target_field_id'] || ''
    end

    def formula
      calculation['formula'] || ''
    end

    def new_calculation?
      calculation['id'].nil?
    end

    def numeric_fields
      fields.select { |f| %w[number integer float decimal].include?(f['property_type']) }
    end
  end
end
```

Create `app/components/page_builder/formula_editor_component.html.erb`:
```erb
<div data-formula-editor-modal
     data-calculation-id="<%= calculation_id %>"
     data-controller="formula-engine"
     data-formula-engine-fields-value="<%= fields.to_json %>"
     class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
  <div class="bg-white rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-hidden flex flex-col">
    <%# Header %>
    <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-gray-900">
        <%= new_calculation? ? 'New Calculation' : 'Edit Calculation' %>
      </h2>
      <button type="button"
              class="p-2 text-gray-400 hover:text-gray-600 transition-colors"
              data-action="click->page-builder#closeFormulaEditor">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>

    <%# Body %>
    <div class="flex-1 overflow-y-auto p-6 space-y-6">
      <%# Target Field %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Target Field</label>
        <select name="target_field"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                data-page-builder-target="calculationTargetField">
          <option value="">Select field...</option>
          <% fields.each do |field| %>
            <option value="<%= field['id'] %>" <%= 'selected' if field['id'] == target_field_id %>>
              <%= field['label'] || field['id'] %>
            </option>
          <% end %>
        </select>
      </div>

      <%# Formula Input %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Formula</label>
        <textarea name="formula"
                  rows="4"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg font-mono text-sm focus:ring-2 focus:ring-indigo-500"
                  placeholder="e.g., SUM(price, tax) * quantity"
                  data-formula-engine-target="input"
                  data-action="input->formula-engine#evaluate"
                  data-page-builder-target="formulaInput"><%= formula %></textarea>
      </div>

      <%# Field References %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">Insert Field</label>
        <div class="flex flex-wrap gap-2">
          <% fields.each do |field| %>
            <button type="button"
                    class="px-2 py-1 text-xs font-mono bg-gray-100 hover:bg-indigo-100 hover:text-indigo-700 rounded transition-colors"
                    data-action="click->page-builder#insertFieldReference"
                    data-field-slug="<%= field['id'] %>">
              <%= field['id'] %>
            </button>
          <% end %>
        </div>
      </div>

      <%# Function Reference %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">Insert Function</label>
        <div class="space-y-3">
          <% functions.each do |category, funcs| %>
            <div>
              <span class="text-xs font-medium text-gray-500 uppercase"><%= category %></span>
              <div class="flex flex-wrap gap-2 mt-1">
                <% funcs.each do |func| %>
                  <button type="button"
                          class="px-2 py-1 text-xs font-mono bg-indigo-50 hover:bg-indigo-100 text-indigo-700 rounded transition-colors"
                          data-action="click->page-builder#insertFunction"
                          data-function="<%= func %>">
                    <%= func %>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%# Preview %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Preview</label>
        <div data-formula-preview
             data-formula-engine-target="preview"
             class="px-3 py-2 bg-gray-50 rounded-lg font-mono text-sm text-gray-600 min-h-[2.5rem]">
          —
        </div>
        <div data-formula-engine-target="error" class="text-xs text-red-500 mt-1"></div>
      </div>
    </div>

    <%# Footer %>
    <div class="px-6 py-4 border-t border-gray-200 flex justify-end gap-3">
      <button type="button"
              class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
              data-action="click->page-builder#closeFormulaEditor">
        Cancel
      </button>
      <button type="button"
              class="px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 transition-colors"
              data-action="click->page-builder#saveCalculation">
        Save
      </button>
    </div>
  </div>
</div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/page_builder/formula_editor_component_spec.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/components/page_builder/formula_editor_component.rb \
        app/components/page_builder/formula_editor_component.html.erb \
        spec/components/page_builder/formula_editor_component_spec.rb
git commit -m "feat: add FormulaEditorComponent modal for editing calculations"
```

---

## Phase 5: Page Builder Integration

### Task 17: Update page_builder_controller.js with Rules Methods

**Files:**
- Modify: `app/javascript/controllers/page_builder_controller.js`

**Step 1: Add new targets and values**

Add to existing targets array:
```javascript
static targets = [
  // ... existing targets ...
  "rulesPanel", "rulesList", "calculationsPanel", "calculationsList",
  "ruleEditorModal", "formulaEditorModal",
  "ruleNameInput", "conditionsLogic", "conditionGroups", "ruleActions",
  "calculationTargetField", "formulaInput"
]

static values = {
  // ... existing values ...
  editingRuleId: String,
  editingCalculationId: String
}
```

**Step 2: Add rule management methods**

```javascript
// ============================================
// RULES MANAGEMENT
// ============================================

openRuleEditor(event) {
  const ruleId = event?.currentTarget?.dataset?.ruleId
  this.editingRuleIdValue = ruleId || ''

  const rule = ruleId
    ? this.configuration.rules?.find(r => r.id === ruleId)
    : this.createDefaultRule()

  this.renderRuleEditorModal(rule)
}

closeRuleEditor() {
  this.editingRuleIdValue = ''
  if (this.hasRuleEditorModalTarget) {
    this.ruleEditorModalTarget.remove()
  }
}

editRule(event) {
  this.openRuleEditor(event)
}

saveRule() {
  const rule = this.collectRuleFromEditor()

  if (!this.configuration.rules) {
    this.configuration.rules = []
  }

  if (this.editingRuleIdValue) {
    // Update existing
    const idx = this.configuration.rules.findIndex(r => r.id === this.editingRuleIdValue)
    if (idx >= 0) {
      this.configuration.rules[idx] = rule
    }
  } else {
    // Create new
    rule.id = `rule_${Date.now()}`
    this.configuration.rules.push(rule)
  }

  this.saveHistory()
  this.closeRuleEditor()
  this.renderRulesPanel()
  this.markDirty()
}

deleteRule(event) {
  const ruleId = event.currentTarget.dataset.ruleId
  if (!confirm('Delete this rule?')) return

  this.configuration.rules = this.configuration.rules.filter(r => r.id !== ruleId)
  this.saveHistory()
  this.renderRulesPanel()
  this.markDirty()
}

toggleRule(event) {
  const ruleId = event.currentTarget.dataset.ruleId
  const rule = this.configuration.rules?.find(r => r.id === ruleId)
  if (rule) {
    rule.enabled = !rule.enabled
    this.saveHistory()
    this.renderRulesPanel()
    this.markDirty()
  }
}

createDefaultRule() {
  return {
    id: null,
    name: '',
    enabled: true,
    conditions: { logic: 'all', groups: [] },
    actions: []
  }
}

collectRuleFromEditor() {
  return {
    id: this.editingRuleIdValue || null,
    name: this.ruleNameInputTarget?.value || 'Unnamed rule',
    enabled: true,
    conditions: this.collectConditionsFromEditor(),
    actions: this.collectActionsFromEditor()
  }
}

// ============================================
// CALCULATIONS MANAGEMENT
// ============================================

openFormulaEditor(event) {
  const calcId = event?.currentTarget?.dataset?.calculationId
  this.editingCalculationIdValue = calcId || ''

  const calc = calcId
    ? this.configuration.calculations?.find(c => c.id === calcId)
    : this.createDefaultCalculation()

  this.renderFormulaEditorModal(calc)
}

closeFormulaEditor() {
  this.editingCalculationIdValue = ''
  if (this.hasFormulaEditorModalTarget) {
    this.formulaEditorModalTarget.remove()
  }
}

editCalculation(event) {
  this.openFormulaEditor(event)
}

saveCalculation() {
  const calc = {
    id: this.editingCalculationIdValue || `calc_${Date.now()}`,
    target_field_id: this.calculationTargetFieldTarget?.value,
    formula: this.formulaInputTarget?.value
  }

  if (!this.configuration.calculations) {
    this.configuration.calculations = []
  }

  if (this.editingCalculationIdValue) {
    const idx = this.configuration.calculations.findIndex(c => c.id === this.editingCalculationIdValue)
    if (idx >= 0) {
      this.configuration.calculations[idx] = calc
    }
  } else {
    this.configuration.calculations.push(calc)
  }

  this.saveHistory()
  this.closeFormulaEditor()
  this.renderCalculationsPanel()
  this.markDirty()
}

deleteCalculation(event) {
  const calcId = event.currentTarget.dataset.calculationId
  if (!confirm('Delete this calculation?')) return

  this.configuration.calculations = this.configuration.calculations.filter(c => c.id !== calcId)
  this.saveHistory()
  this.renderCalculationsPanel()
  this.markDirty()
}

createDefaultCalculation() {
  return {
    id: null,
    target_field_id: '',
    formula: ''
  }
}

insertFieldReference(event) {
  const slug = event.currentTarget.dataset.fieldSlug
  if (this.hasFormulaInputTarget) {
    this.insertAtCursor(this.formulaInputTarget, slug)
  }
}

insertFunction(event) {
  const func = event.currentTarget.dataset.function
  if (this.hasFormulaInputTarget) {
    this.insertAtCursor(this.formulaInputTarget, `${func}()`)
    // Position cursor inside parentheses
    this.formulaInputTarget.selectionStart -= 1
    this.formulaInputTarget.selectionEnd -= 1
  }
}

insertAtCursor(input, text) {
  const start = input.selectionStart
  const end = input.selectionEnd
  const before = input.value.substring(0, start)
  const after = input.value.substring(end)
  input.value = before + text + after
  input.selectionStart = input.selectionEnd = start + text.length
  input.focus()
  input.dispatchEvent(new Event('input', { bubbles: true }))
}

// ============================================
// PANEL RENDERING
// ============================================

renderRulesPanel() {
  if (!this.hasRulesPanelTarget) return

  const rules = this.configuration.rules || []
  // Re-render the RulesPanelComponent or update innerHTML
  // This would typically fetch partial from server or use template
}

renderCalculationsPanel() {
  if (!this.hasCalculationsPanelTarget) return

  const calculations = this.configuration.calculations || []
  // Re-render the CalculationsPanelComponent
}
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/page_builder_controller.js
git commit -m "feat: add rules and calculations management methods to page_builder_controller"
```

---

### Task 18: Update Editor View with Rules/Calculations Panels

**Files:**
- Modify: `app/views/pages/_editor.html.erb`

**Step 1: Add panels to left sidebar**

Find the left sidebar section and add after component library:

```erb
<%# ===== LEFT SIDEBAR ===== %>
<aside class="w-72 bg-white border-r border-gray-200 flex flex-col overflow-hidden">
  <%# ... existing component library ... %>

  <%# Divider %>
  <div class="border-t border-gray-200 mx-4"></div>

  <%# Rules Panel %>
  <div class="p-4" data-page-builder-target="rulesPanel">
    <%= render PageBuilder::RulesPanelComponent.new(
      rules: @page.configuration_json&.dig('rules') || []
    ) %>
  </div>

  <%# Calculations Panel %>
  <div class="p-4 border-t border-gray-100" data-page-builder-target="calculationsPanel">
    <%= render PageBuilder::CalculationsPanelComponent.new(
      calculations: @page.configuration_json&.dig('calculations') || [],
      fields: @page.configuration_json&.dig('pages')&.flat_map { |p| p['fields'] || [] } || []
    ) %>
  </div>
</aside>
```

**Step 2: Add modal containers**

At the end of the editor, before closing div:

```erb
<%# Modal Containers %>
<div data-page-builder-target="ruleEditorModal"></div>
<div data-page-builder-target="formulaEditorModal"></div>
```

**Step 3: Commit**

```bash
git add app/views/pages/_editor.html.erb
git commit -m "feat: add rules and calculations panels to page builder sidebar"
```

---

### Task 19: Create formula_engine_controller.js

**Files:**
- Create: `app/javascript/controllers/formula_engine_controller.js`

**Step 1: Implement controller**

Create `app/javascript/controllers/formula_engine_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"
import { FormulaEngine } from "../lib/formula_engine"

/**
 * Formula Engine Controller
 *
 * Provides live formula preview in the formula editor modal.
 * Evaluates formulas as user types and displays results.
 */
export default class extends Controller {
  static targets = ["input", "preview", "error"]
  static values = {
    fields: { type: Object, default: {} }
  }

  connect() {
    this.evaluate()
  }

  evaluate() {
    if (!this.hasInputTarget || !this.hasPreviewTarget) return

    const formula = this.inputTarget.value

    if (!formula.trim()) {
      this.previewTarget.textContent = '—'
      if (this.hasErrorTarget) this.errorTarget.textContent = ''
      return
    }

    // Create sample values for preview
    const sampleValues = this.createSampleValues()
    const engine = new FormulaEngine(sampleValues)

    try {
      const result = engine.evaluate(formula)

      if (result === null) {
        this.previewTarget.textContent = '(could not evaluate)'
        if (this.hasErrorTarget) this.errorTarget.textContent = ''
      } else {
        this.previewTarget.textContent = this.formatResult(result)
        if (this.hasErrorTarget) this.errorTarget.textContent = ''
      }
    } catch (error) {
      this.previewTarget.textContent = '—'
      if (this.hasErrorTarget) {
        this.errorTarget.textContent = error.message || 'Invalid formula'
      }
    }
  }

  createSampleValues() {
    const values = {}
    const fields = Array.isArray(this.fieldsValue) ? this.fieldsValue : []

    fields.forEach(field => {
      const id = field.id || field['id']
      const type = field.property_type || field['property_type'] || 'string'

      switch (type) {
        case 'number':
        case 'integer':
        case 'float':
        case 'decimal':
          values[id] = 10
          break
        case 'boolean':
          values[id] = true
          break
        case 'date':
          values[id] = new Date().toISOString().slice(0, 10)
          break
        default:
          values[id] = 'sample'
      }
    })

    return values
  }

  formatResult(result) {
    if (typeof result === 'number') {
      return Number.isInteger(result) ? result.toString() : result.toFixed(2)
    }
    if (result instanceof Date) {
      return result.toISOString().slice(0, 10)
    }
    if (typeof result === 'boolean') {
      return result ? 'true' : 'false'
    }
    return String(result)
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/formula_engine_controller.js
git commit -m "feat: add formula_engine_controller for live formula preview"
```

---

### Task 20: System Test for Conditional Logic

**Files:**
- Create: `spec/system/form_conditions_spec.rb`

**Step 1: Write system test**

Create `spec/system/form_conditions_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Form conditional logic', type: :system, js: true do
  let(:customer) { create(:customer) }

  before do
    login_as_customer(customer)
  end

  describe 'field visibility' do
    let(:config) do
      {
        'pages' => [{
          'id' => 'page_1',
          'name' => 'Page 1',
          'fields' => [
            {
              'id' => 'has_pet',
              'property_type' => 'boolean',
              'label' => 'Do you have a pet?'
            },
            {
              'id' => 'pet_name',
              'property_type' => 'string',
              'label' => 'Pet name'
            }
          ]
        }],
        'metadata' => {},
        'rules' => [{
          'id' => 'rule_1',
          'name' => 'Show pet name',
          'enabled' => true,
          'conditions' => {
            'logic' => 'all',
            'groups' => [{
              'logic' => 'all',
              'items' => [{
                'field_id' => 'has_pet',
                'operator' => 'equals',
                'value' => true
              }]
            }]
          },
          'actions' => [{
            'type' => 'show_field',
            'target_id' => 'pet_name'
          }]
        }],
        'calculations' => []
      }
    end

    let!(:page_record) { create(:page, customer: customer, configuration: config.to_json) }

    it 'shows field when condition is met' do
      visit preview_page_path(customer.id, page_record)

      # Pet name should be hidden initially
      expect(page).not_to have_field('Pet name', visible: true)

      # Check the checkbox
      check 'Do you have a pet?'

      # Pet name should now be visible
      expect(page).to have_field('Pet name', visible: true)
    end

    it 'hides field when condition is no longer met' do
      visit preview_page_path(customer.id, page_record)

      check 'Do you have a pet?'
      expect(page).to have_field('Pet name', visible: true)

      uncheck 'Do you have a pet?'
      expect(page).not_to have_field('Pet name', visible: true)
    end
  end

  describe 'calculated fields' do
    let(:config) do
      {
        'pages' => [{
          'id' => 'page_1',
          'fields' => [
            { 'id' => 'quantity', 'property_type' => 'number', 'label' => 'Quantity' },
            { 'id' => 'price', 'property_type' => 'number', 'label' => 'Price' },
            { 'id' => 'total', 'property_type' => 'number', 'label' => 'Total' }
          ]
        }],
        'metadata' => {},
        'rules' => [],
        'calculations' => [{
          'id' => 'calc_1',
          'target_field_id' => 'total',
          'formula' => 'quantity * price'
        }]
      }
    end

    let!(:page_record) { create(:page, customer: customer, configuration: config.to_json) }

    it 'calculates values automatically' do
      visit preview_page_path(customer.id, page_record)

      fill_in 'Quantity', with: '5'
      fill_in 'Price', with: '10'

      # Total should be calculated
      expect(find_field('Total').value).to eq('50')
    end
  end
end
```

**Step 2: Run test**

Run: `bundle exec rspec spec/system/form_conditions_spec.rb`
Expected: All PASS (after all previous tasks completed)

**Step 3: Commit**

```bash
git add spec/system/form_conditions_spec.rb
git commit -m "test: add system tests for conditional logic runtime"
```

---

## Summary

This implementation plan covers:

1. **Phase 1 (Tasks 1-8):** Core JavaScript libraries - ConditionEvaluator and FormulaEngine
2. **Phase 2 (Tasks 9-10):** Ruby model migration and validation
3. **Phase 3 (Tasks 11-12):** Runtime controller and PageContentGenerator integration
4. **Phase 4 (Tasks 13-16):** UI ViewComponents (panels and modals)
5. **Phase 5 (Tasks 17-20):** Page builder integration and system tests

Each task follows TDD with:
- Failing test first
- Minimal implementation
- Verification
- Commit

Total: 20 tasks, ~60 commits when including intermediate steps.
