# Import Path Triage

Use this playbook for PDF, photo, or URL import bugs, suspicious extraction quality, or regressions in fallback behavior.

## Focus

- Identify the exact import path first: PDF text extraction, PDF OCR, photo OCR, URL JSON-LD, URL AI fallback, or manual fallback.
- Isolate the smallest failing layer before editing.
- Protect recipe correctness over clever parsing.

## Workflow

1. Confirm the entry path and parse mode involved: `auto`, `ai`, or `manual`.
2. Inspect the raw intermediate artifact if possible:
   - extracted PDF text by page
   - OCR text
   - JSON-LD payload
   - Claude JSON payload after `JSONPayloadExtractor`
3. Decide whether the failure is:
   - bad source text
   - bad boundary detection
   - bad prompt/AI output handling
   - bad manual parsing heuristics
   - bad normalization after parsing
4. Fix only that layer unless evidence shows the bug crosses layers.
5. Re-check the saved `Recipe`, not just the parser output.

## Validation

- Prefer a narrow sample over a broad regression sweep.
- Check title, servings, ingredient count, step order, and source type.
- For URL imports, verify blocked-host rules still hold.

## Avoid

- changing prompts and manual heuristics in the same pass without clear need
- broad parser rewrites to solve one bad input
- declaring success before checking the saved model shape
