# NodeJS Removal Design

**Date:** 2026-02-24
**Status:** Approved

## Overview

Remove all NodeJS artifacts from the application. The app already follows Rails 8 conventions with importmap-rails, propshaft, and tailwindcss-rails gem - NodeJS was only used for Jest testing.

## Current State

- **NodeJS Usage:** Jest testing only (no build pipeline dependency)
- **Rails 8 Stack:** importmap-rails, propshaft, tailwindcss-rails gem, stimulus-rails, turbo-rails
- **node_modules size:** 54MB

## Files to Delete

| File/Directory | Purpose | Size |
|----------------|---------|------|
| `package.json` | NodeJS manifest (Jest config) | ~600B |
| `package-lock.json` | NodeJS lock file | ~217KB |
| `node_modules/` | NodeJS dependencies | 54MB |
| `spec/javascript/lib/condition_evaluator_spec.js` | Jest tests | ~22KB |
| `spec/javascript/lib/formula_engine_spec.js` | Jest tests | ~12KB |

## Files Unchanged

| File | Current State |
|------|---------------|
| `Gemfile` | Uses `tailwindcss-rails` gem (no Node) |
| `config/importmap.rb` | ESM import maps for JS |
| `app/javascript/` | Stimulus controllers (remain as-is) |
| `app/javascript/lib/` | ConditionEvaluator, FormulaEngine (remain as-is) |

## Architecture

No architectural changes required. The application continues to use:

- **CSS:** TailwindCSS via `tailwindcss-rails` gem
- **JavaScript:** Stimulus via importmap-rails
- **Assets:** Propshaft pipeline

## Testing Impact

- **Removed:** Jest unit tests for ConditionEvaluator and FormulaEngine
- **Retained:** All RSpec tests, system tests with Capybara/Selenium

## Verification

1. Run `bundle exec rspec` - all tests should pass
2. Run `bin/dev` - development server should start, Tailwind should compile
3. Verify application renders correctly in browser

## Decision

Approved: Clean removal approach selected. Remove all NodeJS files and Jest tests completely.
