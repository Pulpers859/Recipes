# SwiftUI Flow Regression

Use this playbook for bugs or changes in `Views/` where state, persistence, async work, and navigation interact.

## Focus

- Follow the user flow end-to-end.
- Verify that UI state and persisted model state stay aligned.

## Workflow

1. Identify the exact entry and exit points of the flow.
2. Trace state ownership:
   - local `@State`
   - `@AppStorage`
   - `@ObservedObject` / `@StateObject`
   - `@EnvironmentObject`
   - `@Environment(\.modelContext)`
3. Check async boundaries and whether UI mutations return to the main actor.
4. Confirm insert/delete/save behavior happens exactly once.
5. Check success, error, empty, and cancel paths.

## Validation

- For import/edit flows, verify the saved recipe matches the edited state.
- For destructive actions, verify the confirmation and aftermath are clear.
- For sheets/full-screen flows, verify dismissal does not hide a failed save or import.

## Avoid

- refactoring view structure unless it removes the actual bug source
- fixing a persistence bug only in the UI layer if the real issue is deeper
- assuming a visible state change means the model was safely updated
