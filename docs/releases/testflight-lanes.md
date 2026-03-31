# ThePerch TestFlight Lanes

## Lanes

### Alpha
- Purpose: Fábio daily-driver builds
- Speed over ceremony
- Default deploy lane in the script
- Safe for frequent internal iteration

### Beta
- Purpose: verified stable builds for broader testing
- Use only after the build has been sanity-checked and is suitable for external feedback
- Must be intentionally selected

## Script usage

Lane selection is required. This is intentional so deploy intent is always explicit.

```bash
bash ~/Documents/Apps/ThePerch/deploy-testflight.sh --lane=alpha
bash ~/Documents/Apps/ThePerch/deploy-testflight.sh --lane=beta
```

## Notes
- Lane selection is currently tracked in deploy output and notifications.
- If App Store Connect tester-group automation is added later, this document is the policy source for that integration.
