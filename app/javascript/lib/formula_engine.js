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

      // Strings (single or double quotes)
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

      // Field reference token: {field_id}
      if (formula[pos] === '{') {
        pos++ // skip {
        let ident = ''
        while (pos < formula.length && formula[pos] !== '}') {
          ident += formula[pos++]
        }
        pos++ // skip }
        tokens.push({ type: 'IDENTIFIER', value: ident.trim() })
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

      MOD: (a, b) => Number(a) % Number(b),

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
      },

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
    }
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

  parse(tokens) {
    let pos = 0

    const parseExpression = () => parseComparison()

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
      if (!token) throw new Error('Unexpected end of expression')

      // Parenthesized expression
      if (token.type === 'LPAREN') {
        pos++
        const expr = parseExpression()
        if (tokens[pos]?.type !== 'RPAREN') throw new Error('Expected )')
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
          if (tokens[pos]?.type === 'COMMA') pos++
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
        return value === undefined ? null : value
      }

      case 'BINARY': {
        const left = this.execute(node.left)
        const right = this.execute(node.right)

        // Handle null in comparisons
        if (left === null || right === null) {
          if (['==', '!='].includes(node.operator)) {
            return node.operator === '==' ? left === right : left !== right
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
}

// Converts legacy bare-identifier formulas to {field_id} token form, given the
// set of known field ids. Functions and numbers are left untouched.
export function normalizeFormula(formula, fieldIds = []) {
  if (!formula) return formula
  const known = new Set(fieldIds)
  return formula.replace(/(?<![A-Za-z0-9_{])([a-zA-Z_][a-zA-Z0-9_]*)(?!\s*\()/g,
    (m, id) => (known.has(id) ? `{${id}}` : m))
}
