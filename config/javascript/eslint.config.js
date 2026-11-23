// Dev-only ESLint config (the app ships JS via importmap — there is no JS build
// step). This lints for *correctness* and *dead code* — unused vars/functions,
// undefined references, unreachable code, duplicate keys — rather than imposing
// a stylistic standard, since the codebase deliberately follows the Hotwire
// no-semicolon / double-quote convention. Run with:
//   npm run lint
// or
//   npx eslint --config config/javascript/eslint.config.js app/javascript
import js from "@eslint/js"
import globals from "globals"

export default [
  js.configs.recommended,
  {
    files: ["app/javascript/**/*.js"],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: "module",
      globals: {
        ...globals.browser,
        // App-level globals provided at runtime (importmap / CDN / Stimulus).
        Stimulus: "readonly",
        Turbo: "readonly",
        mermaid: "readonly",
      },
    },
    rules: {
      // Surface dead code without auto-deleting (a "_"-prefixed name opts out,
      // including intentionally-ignored caught errors like `catch (_e)`).
      "no-unused-vars": ["warn", {
        argsIgnorePattern: "^_",
        varsIgnorePattern: "^_",
        caughtErrorsIgnorePattern: "^_",
      }],
    },
  },
]
