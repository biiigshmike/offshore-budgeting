#!/usr/bin/env bash
set -euo pipefail

CATALOG_PATH="${1:-OffshoreBudgeting/Localizable.xcstrings}"

if [[ ! -f "$CATALOG_PATH" ]]; then
  echo "error: catalog not found at '$CATALOG_PATH'" >&2
  exit 2
fi

python3 - "$CATALOG_PATH" <<'PY'
import json
import re
import sys
from pathlib import Path

catalog_path = Path(sys.argv[1])
data = json.loads(catalog_path.read_text(encoding="utf-8"))
strings = data.get("strings", {})
widget_catalog_path = Path("OffshoreBudgetingWidgets/Localizable.xcstrings")

# Keep brand/product names untranslated.
es_equals_key_allowlist = {
    "",
    "%@",
    "%@ - %@",
    "%@ • %@",
    "%@, %@",
    "%@:",
    "%@↑",
    "%@↓",
    "$↑",
    "$↓",
    "0%",
    "100%",
    "A-Z",
    "A–Z",
    "Apple Card",
    "Color",
    "Error",
    "F↑",
    "F↓",
    "General",
    "Offshore",
    "Offshore Widgets",
    "PreviewSeed did not create a Workspace + Category.",
    "PreviewSeed did not create a Workspace.",
    "PreviewSeed.seedBasicData(in:) didn’t create a Card.",
    "PreviewSeed.seedBasicData(in:) didn’t create a Preset.",
    "Total",
    "Variable",
    "Z-A",
    "Z–A",
    "•",
    "iCloud",
    "notification.appName",
}

variant_pairs = [
    ("A-Z", "A–Z"),
    ("Z-A", "Z–A"),
    ("$ ↑", "$↑"),
    ("$ ↓", "$↓"),
]

placeholder_pattern = re.compile(r"%(?:\\d+\\$)?(?:[@dDuUxXfFeEgGcCsSpaA])")
preset_term_pattern = re.compile(r"\\b(?:preset|presets|preajuste|preajustes)\\b", re.IGNORECASE)

required_widget_keys = [
    "Income",
    "Spend Trends",
    "Card",
    "Next Planned Expense",
    "Income Widget",
    "Spend Trends Widget",
    "Card Widget",
    "Next Planned Expense Widget",
    "Track planned vs actual income for a selected period.",
    "Track spending trends and top categories for a selected period.",
    "Show a card preview with spending for a selected period.",
    "Show upcoming planned expenses for all cards or a selected card.",
]

def extract_placeholders(text: str) -> list[str]:
    return sorted(placeholder_pattern.findall(text or ""))

total = len(strings)
es_missing = 0
es_equals_key = 0
es_equals_en = 0
placeholder_mismatches = 0
variant_coverage_issues = 0
glossary_issues = 0
widget_coverage_issues = 0
source_coverage_issues = 0

es_equals_key_items: list[str] = []
es_equals_en_items: list[str] = []
es_missing_items: list[str] = []
placeholder_mismatch_items: list[str] = []
variant_issue_items: list[str] = []
glossary_issue_items: list[str] = []
widget_issue_items: list[str] = []
source_issue_items: list[str] = []

for key, entry in strings.items():
    locs = entry.get("localizations", {})
    en_value = locs.get("en", {}).get("stringUnit", {}).get("value")
    es_value = locs.get("es", {}).get("stringUnit", {}).get("value")

    source_text = en_value if isinstance(en_value, str) else key

    if es_value is None:
        es_missing += 1
        es_missing_items.append(key)
        continue

    if es_value == key and key not in es_equals_key_allowlist:
        es_equals_key += 1
        es_equals_key_items.append(key)

    if isinstance(en_value, str) and es_value == en_value and key not in es_equals_key_allowlist:
        es_equals_en += 1
        es_equals_en_items.append(key)

    if extract_placeholders(source_text) != extract_placeholders(es_value):
        placeholder_mismatches += 1
        placeholder_mismatch_items.append(key)

    # Glossary lock: no preset/preajuste terms in user-facing Spanish.
    if preset_term_pattern.search(es_value):
        glossary_issues += 1
        glossary_issue_items.append(f"{key} => {es_value}")

    # Glossary lock: Home-context copy should use "Panel" terminology.
    if key == "app.section.home" or "home" in key.lower():
        if "inicio" in es_value.lower():
            glossary_issues += 1
            glossary_issue_items.append(f"{key} => {es_value}")

for left, right in variant_pairs:
    left_present = left in strings
    right_present = right in strings
    if left_present != right_present:
        variant_coverage_issues += 1
        variant_issue_items.append(f"{left} vs {right}")

if widget_catalog_path.exists():
    widget_data = json.loads(widget_catalog_path.read_text(encoding="utf-8"))
    widget_strings = widget_data.get("strings", {})
    for key in required_widget_keys:
        entry = widget_strings.get(key, {})
        es_value = entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("value")
        if not isinstance(es_value, str) or not es_value.strip():
            widget_coverage_issues += 1
            widget_issue_items.append(key)
else:
    widget_coverage_issues += 1
    widget_issue_items.append("missing OffshoreBudgetingWidgets/Localizable.xcstrings")

# Guard against common regressions in critical user-facing views.
source_watchlist = {
    "OffshoreBudgeting/CoreViews/Cards/AccountsView.swift": [
        'case sharedBalances = "Reconciliations"',
        '.accessibilityLabel("Sort Unavailable")',
    ],
    "OffshoreBudgeting/CoreViews/Budgets/BudgetsView.swift": [
        'title: "Past Budgets (',
        'title: "Upcoming Budgets (',
        'title: "Active Budgets (',
    ],
    "OffshoreBudgeting/CoreViews/Budgets/BudgetDetailView.swift": [
        'Text("Overview • ',
        '.init(label: "Projected Savings"',
        '.init(label: "Actual Savings"',
    ],
    "OffshoreBudgeting/CoreViews/Home/HomeView.swift": [
        'Text("Widgets")',
        'Text("Tap Edit to pin widgets and cards to Home.")',
    ],
    "OffshoreBudgeting/CoreViews/Settings/SettingsView.swift": [
        'title: "Manage Categories"',
        'Label("Manage Workspaces",',
    ],
    "OffshoreBudgeting/CoreViews/Settings/SettingsHelpView.swift": [
        'Text("No matching help topics.")',
        'Section("Getting Started")',
        'Section("Core Screens")',
    ],
    "OffshoreBudgeting/CoreViews/Settings/SettingsGeneralView.swift": [
        'private func maintenanceButton(title: String, tint: Color, action: @escaping () -> Void)',
    ],
    "OffshoreBudgeting/CoreViews/Settings/SettingsPrivacyView.swift": [
        'private func permissionRow(title: String, status: String, description: String)',
    ],
}

source_regex_watchlist = {
    "OffshoreBudgeting/CoreViews/Settings/SettingsView.swift": [
        r'SettingsRow\(\s*title:\s*"',
    ],
}

for relative_path, blocked_values in source_watchlist.items():
    source_path = Path(relative_path)
    if not source_path.exists():
        continue
    content = source_path.read_text(encoding="utf-8")
    for blocked in blocked_values:
        if blocked in content:
            source_coverage_issues += 1
            source_issue_items.append(f"{relative_path} contains '{blocked}'")

for relative_path, blocked_patterns in source_regex_watchlist.items():
    source_path = Path(relative_path)
    if not source_path.exists():
        continue
    content = source_path.read_text(encoding="utf-8")
    for blocked_pattern in blocked_patterns:
        if re.search(blocked_pattern, content, re.MULTILINE | re.DOTALL):
            source_coverage_issues += 1
            source_issue_items.append(f"{relative_path} matches /{blocked_pattern}/")

print(f"catalog: {catalog_path}")
print(f"total keys: {total}")
print(f"es missing: {es_missing}")
print(f"es equals key (non-allowlisted): {es_equals_key}")
print(f"es equals en (non-allowlisted): {es_equals_en}")
print(f"placeholder mismatches: {placeholder_mismatches}")
print(f"variant coverage issues: {variant_coverage_issues}")
print(f"glossary issues: {glossary_issues}")
print(f"widget coverage issues: {widget_coverage_issues}")
print(f"source coverage issues: {source_coverage_issues}")

if es_missing_items:
    print("\\nMissing es items:")
    for item in es_missing_items[:50]:
        print(f"- {item}")

if es_equals_key_items:
    print("\\nTop es==key items:")
    for item in es_equals_key_items[:20]:
        print(f"- {item}")

if es_equals_en_items:
    print("\\nTop es==en items:")
    for item in es_equals_en_items[:20]:
        print(f"- {item}")

if placeholder_mismatch_items:
    print("\\nTop placeholder mismatch items:")
    for item in placeholder_mismatch_items[:20]:
        print(f"- {item}")

if variant_issue_items:
    print("\\nVariant key issues:")
    for item in variant_issue_items[:20]:
        print(f"- {item}")

if glossary_issue_items:
    print("\\nGlossary issues:")
    for item in glossary_issue_items[:20]:
        print(f"- {item}")

if widget_issue_items:
    print("\\nWidget coverage issues:")
    for item in widget_issue_items[:20]:
        print(f"- {item}")

if source_issue_items:
    print("\\nSource coverage issues:")
    for item in source_issue_items[:20]:
        print(f"- {item}")

if (
    es_missing > 0
    or es_equals_key > 0
    or es_equals_en > 0
    or placeholder_mismatches > 0
    or variant_coverage_issues > 0
    or glossary_issues > 0
    or widget_coverage_issues > 0
    or source_coverage_issues > 0
):
    sys.exit(1)
PY
