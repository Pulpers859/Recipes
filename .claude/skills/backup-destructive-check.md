# Backup And Destructive Check

Use this playbook for delete-all flows, duplicate merging, backup/import/export changes, pantry backup work, or any change that could remove or overwrite user data.

## Focus

- Prevent hidden data loss.
- Keep irreversible behavior explicit, narrow, and explainable.

## Workflow

1. List every destructive or overwrite path touched by the change.
2. Identify the recovery path that exists today:
   - recipe JSON backup
   - pantry backup file
   - explicit confirmation UI
3. If there is no real recovery path, prefer a smaller change or a clearer warning over more automation.
4. Make results countable and user-visible when items are skipped, merged, or deleted.
5. Keep side effects local; do not add background cleanup jobs.

## Validation

- Check counts before and after destructive actions.
- Check that dedupe keeps the highest-quality record.
- Check exported backup files remain readable and deterministic.

## Avoid

- silent cleanup
- hidden hooks or background repair jobs
- broad "auto-fix" behavior that is hard to audit later
