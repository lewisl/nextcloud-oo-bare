# 2025-09-27 – Editor UX tuning

## Changes
- `src/07_integration_config.sh`: flip the OnlyOffice `sameTab` flag on so editors stay inside the original Nextcloud tab, matching the documented close-button behaviour.
- `project-status-and-todo/CURRENT_BEST_CONFIGURATIONS.md`: noted that `sameTab` must remain `true` in our reference configuration.

## Validation
- Re-ran `sudo ./src/07_integration_config.sh`; connector check and nginx smoke tests still succeed, and `occ config:app:get onlyoffice sameTab` now returns `true`.
