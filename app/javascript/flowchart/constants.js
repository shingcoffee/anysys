/**
 * Constants and configuration for the flowchart canvas.
 *
 * `flowchart/constants` and `flowchart/constants/index` are both valid
 * importmap specifiers and both are used across the codebase, so this file
 * simply forwards to the directory barrel — one export list, two entry points.
 *
 * Import from here or directly from the subdirectory modules:
 * - ./constants/canvas - Canvas configuration
 * - ./constants/elements - Element configuration
 * - ./constants/element_registry - Element catalog store
 */

export * from "flowchart/constants/index"
