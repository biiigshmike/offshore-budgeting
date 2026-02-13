# Help Authoring Workflow

This project uses one help content source for both:
- Generated Help Book bundle (`OffshoreHelp.help`)
- In-app Help (`SettingsHelpView`)

## Source of Truth

Edit markdown files in:
- `HelpSource/en/`

Topic metadata is in:
- `HelpSource/help_manifest.json`

## Regenerate Outputs

Run from repo root:

```bash
xcrun swift scripts/generate_help.swift
```

This regenerates:
- `OffshoreBudgeting/CoreViews/Settings/GeneratedHelpContent.swift`
- `OffshoreHelp.help/`

## Screenshot Mapping

For section screenshots, use this marker in markdown:

```text
[[screenshot:1]]
```

The generator maps topic title + slot to asset sets:
- `Help-<TopicTitleWithoutSpaces>-<slot>.imageset`

Example for `Home`, slot 2:
- `OffshoreBudgeting/Assets.xcassets/Help-Home-2.imageset`

## Commit Policy

When markdown or manifest changes, commit all of these together:
- `HelpSource/...`
- `OffshoreBudgeting/CoreViews/Settings/GeneratedHelpContent.swift`
- `OffshoreHelp.help/...`

## Validation Checklist

1. Regenerate help outputs.
2. Build app:
   - `xcodebuild -project OffshoreBudgeting.xcodeproj -scheme OffshoreBudgeting -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/OffshoreDerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY= build`
3. Open Settings > Help and confirm topics and search.
4. On iPad or Mac Catalyst, verify Help > Offshore Help opens the in-app help sheet.
