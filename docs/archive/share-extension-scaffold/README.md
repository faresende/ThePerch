# Archived Share Extension scaffolds

These two directories were drafted as part of an iOS Share Extension
that was never wired into the Xcode project (verified: only `ThePerch`,
`ThePerchWidgets`, `PerchSharedKit`, and `ThePerchTests` are
`PBXNativeTarget`s). The code wrote to a now-renamed `records` table
and used non-team-prefixed keychain access groups that would have
failed silently on a real device.

If you want to add a Share Extension to your fork:

1. Use these files as a starting reference, but expect significant rework.
2. The keychain-access-group must be team-prefixed (`$(AppIdentifierPrefix)group.com.theperch.shared`).
3. Write to `dashboard_records`, not `records`.
4. Wire the target into `ThePerch.xcodeproj` and add a matching
   `.entitlements` file with `com.apple.security.application-groups`
   and `keychain-access-groups`.
