# TestFlight — coming later

The Perch does not currently have a public TestFlight link. For now, the only supported install path is **build from source in Xcode** — see [../SHARE.md](../SHARE.md#path-a--just-the-ios-app-demo-data) for the steps.

## Why not yet?

TestFlight requires an active Apple Developer Program membership ($99/yr) and some App Store Connect plumbing (external tester groups, builds, a privacy manifest, a screenshot, a review note). It's on the roadmap, not done.

## When it exists, this section will contain:

- The public TestFlight URL
- The current build number and what's in it
- Minimum iOS version
- Known issues in the current build

## If you want to help get TestFlight set up

The work is:

1. Enroll the repo owner's Apple Developer account.
2. Configure App Store Connect: app record, Team ID, bundle ID.
3. Set up a CI pipeline (Xcode Cloud or GitHub Actions with fastlane) to push builds.
4. Write a privacy manifest and answer the standard TestFlight review questions.
5. Add an external tester group with a public link.

If you've done this before and want to help, open an issue and tag it `testflight`.

## Until then

Building from source is not hard if you have a Mac with Xcode:

```bash
git clone <repo-url>
cd ThePerch
open ios/ThePerch/ThePerch.xcodeproj
# In Xcode: select iPhone simulator, press ⌘R
```

See [SHARE.md](../SHARE.md) for the rest of the install.
