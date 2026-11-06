#!/usr/bin/env bash
set -euo pipefail

# Usage: localization_audit.sh [catalog.xcstrings [locale]]
# With no arguments, audit app + widget catalogs for all project languages.
# Run from any directory. Relative catalog arguments remain relative to the caller.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_LOCALE="${2:-}"
if [[ -n "${1:-}" ]]; then
  CATALOG_PATHS=("$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve())' "$1")")
else
  CATALOG_PATHS=("$REPO_ROOT/OffshoreBudgeting/Localizable.xcstrings" "$REPO_ROOT/OffshoreBudgetingWidgets/Localizable.xcstrings")
fi
cd "$REPO_ROOT"

run_audit() {
  local target_locale="$1"
  python3 - "$CATALOG_PATH" "$target_locale" <<'PY'
import json
import re
import sys
from pathlib import Path

catalog_path = Path(sys.argv[1]).resolve()
target_locale = sys.argv[2]
data = json.loads(catalog_path.read_text(encoding="utf-8"))
strings = data.get("strings", {})
widget_catalog_path = Path("OffshoreBudgetingWidgets/Localizable.xcstrings").resolve()
app_catalog_path = Path("OffshoreBudgeting/Localizable.xcstrings").resolve()
generated_help_path = Path("OffshoreBudgeting/CoreViews/Settings/GeneratedHelpContent.swift")
release_logs_path = Path("OffshoreBudgeting/CoreViews/Settings/SettingsReleaseLogsView.swift")
about_view_path = Path("OffshoreBudgeting/CoreViews/Settings/SettingsAboutView.swift")

# Keep brand/product names untranslated.
es_equals_key_allowlist = {
    "",
    "%@",
    "$ ↑",
    "$ ↓",
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
    "1",
    "A-Z",
    "A–Z",
    "Apple Card",
    "Apple Intelligence",
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
    "What If",
    "•",
    "iCloud",
    "notification.appName",
    "cardEffect.metal",
    "cardTheme.aqua",
    "cardTheme.aster",
    "sort.dateShort.asc",
    "sort.dateShort.desc",
}

fr_equals_key_allowlist = {
    "",
    "%@",
    "%@ - %@",
    "%@ • %@",
    "%@, %@",
    "%@:",
    "%@↑",
    "%@↓",
    "$ ↑",
    "$ ↓",
    "$↑",
    "$↓",
    "0%",
    "100%",
    "1",
    "A-Z",
    "A–Z",
    "Action",
    "Apple Intelligence",
    "Apple Card",
    "Budget",
    "Budgets",
    "Date",
    "Date ↑",
    "Date ↓",
    "Dates",
    "Description",
    "Destination",
    "Direction",
    "F↑",
    "F↓",
    "General",
    "Introduction",
    "iCloud",
    "Maintenance",
    "Max",
    "Maximum",
    "Min",
    "Minimum",
    "Note",
    "Notifications",
    "Offshore",
    "Photos",
    "Source",
    "Section",
    "Total",
    "Type",
    "Variable",
    "Version",
    "Widgets",
    "What If",
    "Z-A",
    "Z–A",
    "OK",
    "30 min",
    "Configuration",
    "•",
    "notification.appName",
    "common.max",
    "common.min",
    "common.ok",
    "common.section",
    "common.total",
    "common.type",
    "common.variable",
    "expenseScope.variable",
    "home.widgets.header",
    "homeWidget.categoryAvailability.ok",
    "sort.dateShort.asc",
    "sort.dateShort.desc",
    "settings.icloud",
    "settings.notifications",
    "app.section.budgets",
    "cardEffect.metal",
    "cardTheme.aqua",
    "cardTheme.aster",
    "cardTheme.ultraviolet",
}

de_equals_key_allowlist = {
    "",
    "%@",
    "%@ - %@",
    "%@ • %@",
    "%@, %@",
    "%@:",
    "%@↑",
    "%@↓",
    "$ ↑",
    "$ ↓",
    "$↑",
    "$↓",
    "0%",
    "100%",
    "1",
    "A-Z",
    "A–Z",
    "Apple Card",
    "Apple Intelligence",
    "Budget",
    "Budgets",
    "F↓",
    "Max",
    "Min",
    "Name",
    "OK",
    "Offshore",
    "Offshore Widgets",
    "Screenshot",
    "Status",
    "Trend",
    "Trends",
    "Version",
    "What If",
    "Widgets",
    "Z-A",
    "Z–A",
    "app.section.budgets",
    "common.max",
    "common.min",
    "common.name",
    "home.widgets.header",
    "homeSavingsOutlook.trends",
    "homeWidget.income.trends",
    "iCloud",
    "notification.appName",
    "settings.icloud",
    "•",
    "whatIf.categoryRow.minMaxFormat",
    "cardTheme.aqua",
    "cardTheme.aster",
    "sort.dateShort.asc",
    "sort.dateShort.desc",
}

ar_equals_key_allowlist = {
    "",
    "%@",
    "%@ - %@",
    "%@ • %@",
    "%@, %@",
    "%@:",
    "%@↑",
    "%@↓",
    "$ ↑",
    "$ ↓",
    "$↑",
    "$↓",
    "0%",
    "100%",
    "1",
    "Apple Card",
    "Apple Intelligence",
    "Offshore",
    "Offshore Widgets",
    "Z-A",
    "iCloud",
    "notification.appName",
    "settings.icloud",
    "•",
}

pt_br_equals_key_allowlist = {
    "",
    "%@",
    "%@ - %@",
    "%@ • %@",
    "%@, %@",
    "%@:",
    "%@↑",
    "%@↓",
    "$ ↑",
    "$ ↓",
    "$↑",
    "$↓",
    "0%",
    "100%",
    "1",
    "A-Z",
    "A–Z",
    "Apple Card",
    "Apple Intelligence",
    "F↑",
    "F↓",
    "Offshore",
    "Offshore Widgets",
    "cardEffect.metal",
    "OK",
    "Status",
    "Total",
    "Widgets",
    "Z-A",
    "Z–A",
    "cardTheme.aqua",
    "common.ok",
    "common.total",
    "home.widgets.header",
    "homeWidget.categoryAvailability.ok",
    "iCloud",
    "notification.appName",
    "settings.icloud",
    "sort.dateShort.asc",
    "sort.dateShort.desc",
    "•",
}

zh_hans_equals_key_allowlist = {
    "",
    "%@",
    "%@ - %@",
    "%@ • %@",
    "%@, %@",
    "%@:",
    "%@↑",
    "%@↓",
    "$ ↑",
    "$ ↓",
    "$↑",
    "$↓",
    "0%",
    "100%",
    "1",
    "A-Z",
    "A–Z",
    "Apple Card",
    "Apple Intelligence",
    "F↑",
    "F↓",
    "Offshore",
    "Offshore Widgets",
    "Z-A",
    "Z–A",
    "iCloud",
    "notification.appName",
    "settings.icloud",
    "sort.dateShort.asc",
    "sort.dateShort.desc",
    "cardEffect.metal",
    "cardTheme.aqua",
    "cardTheme.aster",
    "cardTheme.ultraviolet",
    "•",
}

equals_key_allowlist = {
    "es": es_equals_key_allowlist,
    "fr": fr_equals_key_allowlist,
    "de": de_equals_key_allowlist,
    "ar": ar_equals_key_allowlist,
    "pt-BR": pt_br_equals_key_allowlist,
    "zh-Hans": zh_hans_equals_key_allowlist,
}.get(target_locale, set())

# Brand names and valid words shared with English are intentionally unchanged.
equals_key_allowlist |= {"Offshore Savings"}
equals_key_allowlist |= {
    "es": {"Hospital", "Hotel", "Personal", "Spa"},
    "de": {"Museum", "Optional", "Start"},
    "fr": {"Message"},
    "pt-BR": {"Email", "Hospital", "Hotel", "Marina", "Spa"},
}.get(target_locale, set())

# Match complete printf tokens, including positional, precision and length forms.
# Escaped %% is consumed as one token, never as a following placeholder.
placeholder_pattern = re.compile(
    r"%(?:#@(?P<substitution>[^@]+)@|(?:(?P<position>\d+)\$)?[-+#0 ']*"
    r"(?P<width>\*(?:\d+\$)?|\d+)?"
    r"(?:\.(?P<precision>\*(?:\d+\$)?|\d+))?"
    r"(?P<length>hh|ll|[hljztLq])?(?P<type>[@diuoxXfFeEgGaAcCsSpDUO%]))"
)
preset_term_pattern = re.compile(r"\b(?:preset|presets|preajuste|preajustes)\b", re.IGNORECASE)

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

plist_supported_locales = {"es", "fr", "de", "ar", "pt-BR", "zh-Hans"}
app_plist_required_keys = {
    "CFBundleDisplayName",
    "NSFaceIDUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSPhotoLibraryUsageDescription",
}
widget_plist_required_keys = {
    "CFBundleDisplayName",
}

def extract_placeholders(text: str) -> list[tuple[int, str]]:
    arguments = []
    next_position = 1
    for match in placeholder_pattern.finditer(text or ""):
        if match["substitution"]:
            arguments.append((0, "substitution:" + match["substitution"]))
            continue
        if match["type"] == "%":
            continue
        for field in ("width", "precision"):
            value = match[field] or ""
            if value.startswith("*"):
                position = int(value[1:-1]) if value.endswith("$") else next_position
                arguments.append((position, "d"))
                if not value.endswith("$"):
                    next_position += 1
        position = int(match["position"]) if match["position"] else next_position
        kind = "d" if match["type"] == "i" else match["type"]
        arguments.append((position, (match["length"] or "") + kind))
        if not match["position"]:
            next_position += 1
    return sorted(arguments)


def string_units(node, path=()):
    """Yield direct units and units inside plural/device/substitution variants."""
    if not isinstance(node, dict):
        return
    if "stringUnit" in node:
        yield path, node["stringUnit"]
    for name, child in node.items():
        if name != "stringUnit" and isinstance(child, dict):
            yield from string_units(child, path + (name,))


def missing_plural_fallbacks(node, path=()):
    if not isinstance(node, dict):
        return
    plural = node.get("variations", {}).get("plural")
    if isinstance(plural, dict) and "other" not in plural:
        yield path + ("variations", "plural", "other")
    for name, child in node.items():
        if isinstance(child, dict):
            yield from missing_plural_fallbacks(child, path + (name,))


def source_for_variant(source_units, path, fallback):
    if path in source_units:
        return source_units[path].get("value", fallback)
    # Target languages can require more plural categories than English.
    other_path = tuple("other" if i >= 2 and path[i - 2:i] == ("variations", "plural") else part
                       for i, part in enumerate(path))
    return source_units.get(other_path, source_units.get((), {})).get("value", fallback)


def unchanged_is_allowed(key, source_text):
    if key in equals_key_allowlist or source_text in equals_key_allowlist:
        return True
    # Placeholder-only and punctuation-only strings do not need translation.
    return not any(char.isalpha() for char in placeholder_pattern.sub("", source_text))


def extract_generated_help_strings(source_path: Path) -> list[str]:
    if not source_path.exists():
        return []

    content = source_path.read_text(encoding="utf-8")
    pattern = re.compile(
        r'\b(?:title|header|body|bodyText|displayTitle|fullscreenCaptionText):\s*"((?:[^"\\]|\\.)*)"',
        re.MULTILINE | re.DOTALL,
    )
    seen: dict[str, None] = {}
    for match in pattern.finditer(content):
        value = json.loads(f'"{match.group(1)}"')
        seen.setdefault(value, None)
    return list(seen.keys())


def extract_release_log_strings(source_path: Path) -> list[str]:
    if not source_path.exists():
        return []

    content = source_path.read_text(encoding="utf-8")
    pattern = re.compile(
        r'\b(?:title|description):\s*"((?:[^"\\]|\\.)*)"',
        re.MULTILINE | re.DOTALL,
    )
    seen: dict[str, None] = {}
    for match in pattern.finditer(content):
        value = json.loads(f'"{match.group(1)}"')
        seen.setdefault(value, None)

    header_pattern = re.compile(
        r'NSLocalizedString\("((?:[^"\\]|\\.)*)",\s*comment:\s*""\)'
    )
    for match in header_pattern.finditer(content):
        value = json.loads(f'"{match.group(1)}"')
        seen.setdefault(value, None)

    return list(seen.keys())


def extract_about_strings(source_path: Path) -> list[str]:
    if not source_path.exists():
        return []

    content = source_path.read_text(encoding="utf-8")
    seen: dict[str, None] = {}

    about_row_pattern = re.compile(
        r'AboutRow\(\s*systemImage:\s*"[^"]+",\s*title:\s*"((?:[^"\\]|\\.)*)"\s*\)',
        re.MULTILINE | re.DOTALL,
    )
    for match in about_row_pattern.finditer(content):
        value = json.loads(f'"{match.group(1)}"')
        seen.setdefault(value, None)

    for pattern in [
        re.compile(r'LabeledContent\("((?:[^"\\]|\\.)*)",\s*value:'),
        re.compile(r'\.navigationTitle\("((?:[^"\\]|\\.)*)"\)'),
    ]:
        for match in pattern.finditer(content):
            value = json.loads(f'"{match.group(1)}"')
            seen.setdefault(value, None)

    return list(seen.keys())


def extract_widget_source_strings(source_roots: list[Path]) -> list[tuple[Path, str]]:
    patterns = [
        re.compile(r'(?:widgetLocalized|widgetLocalizedFormat|cardWidgetLocalized|incomeWidgetLocalized|incomeWidgetLocalizedFormat|nextPlannedLocalized|nextPlannedLocalizedFormat|liveActivityLocalized|spendTrendsLocalizedFormat)\("((?:[^"\\]|\\.)*)"'),
        re.compile(r'NSLocalizedString\("((?:[^"\\]|\\.)*)",\s*comment:'),
        re.compile(r'static var title:\s*LocalizedStringResource\s*=\s*"((?:[^"\\]|\\.)*)"'),
        re.compile(r'IntentDescription\("((?:[^"\\]|\\.)*)"\)'),
        re.compile(r'@Parameter\(title:\s*"((?:[^"\\]|\\.)*)"'),
        re.compile(r'TypeDisplayRepresentation\s*\{\s*"((?:[^"\\]|\\.)*)"\s*\}'),
        re.compile(r'\.\w+:\s*"((?:[^"\\]|\\.)*)"'),
    ]
    seen: dict[tuple[str, str], None] = {}

    for root in source_roots:
        if root.is_file():
            candidate_paths = [root]
        elif root.exists():
            candidate_paths = sorted(root.rglob("*.swift"))
        else:
            candidate_paths = []

        for source_path in candidate_paths:
            content = source_path.read_text(encoding="utf-8")
            for pattern in patterns:
                for match in pattern.finditer(content):
                    value = json.loads(f'"{match.group(1)}"')
                    seen.setdefault((str(source_path), value), None)

    return [(Path(path), value) for path, value in seen.keys()]


def parse_strings_file(source_path: Path) -> dict[str, str]:
    if not source_path.exists():
        return {}

    content = source_path.read_text(encoding="utf-8")
    pattern = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";')
    parsed: dict[str, str] = {}
    for match in pattern.finditer(content):
        key = json.loads(f'"{match.group(1)}"')
        value = json.loads(f'"{match.group(2)}"')
        parsed[key] = value
    return parsed

total = len(strings)
missing_count = 0
equals_key_count = 0
equals_en_count = 0
placeholder_mismatches = 0
review_issues = 0
glossary_issues = 0
widget_coverage_issues = 0
plist_coverage_issues = 0
source_coverage_issues = 0

equals_key_items: list[str] = []
equals_en_items: list[str] = []
missing_items: list[str] = []
placeholder_mismatch_items: list[str] = []
review_issue_items: list[str] = []
glossary_issue_items: list[str] = []
widget_issue_items: list[str] = []
plist_issue_items: list[str] = []
source_issue_items: list[str] = []

source_language = data.get("sourceLanguage", "en")
for key, entry in strings.items():
    if entry.get("shouldTranslate") is False:
        continue
    locs = entry.get("localizations", {})
    source_units = dict(string_units(locs.get(source_language, {})))
    target_units = list(string_units(locs.get(target_locale, {})))
    for path in missing_plural_fallbacks(locs.get(target_locale, {})):
        missing_count += 1
        missing_items.append(key + " [" + "/".join(path) + "]")
    if not target_units:
        missing_count += 1
        missing_items.append(key)
        continue

    for path, unit in target_units:
        label = key + (" [" + "/".join(path) + "]" if path else "")
        source_text = source_for_variant(source_units, path, key)
        target_value = unit.get("value")
        if not isinstance(target_value, str) or (source_text.strip() and not target_value.strip()):
            missing_count += 1
            missing_items.append(label)
            continue
        if unit.get("state") != "translated":
            review_issues += 1
            review_issue_items.append(f"{label}: {unit.get('state', 'missing state')}")

        allowed = unchanged_is_allowed(key, source_text)
        if target_value == key and not allowed:
            equals_key_count += 1
            equals_key_items.append(label)
        if target_value == source_text and source_text != key and not allowed:
            equals_en_count += 1
            equals_en_items.append(label)
        if extract_placeholders(source_text) != extract_placeholders(target_value):
            placeholder_mismatches += 1
            placeholder_mismatch_items.append(label)
        if target_locale == "es":
            if preset_term_pattern.search(target_value):
                glossary_issues += 1
                glossary_issue_items.append(f"{label} => {target_value}")
            if key == "app.section.home" or "home" in key.lower():
                if len(target_value.split()) <= 3 and "inicio" in target_value.lower():
                    glossary_issues += 1
                    glossary_issue_items.append(f"{label} => {target_value}")

if widget_catalog_path.exists():
    widget_data = json.loads(widget_catalog_path.read_text(encoding="utf-8"))
    widget_strings = widget_data.get("strings", {})
    for key, entry in widget_strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        units = list(string_units(entry.get("localizations", {}).get(target_locale, {})))
        if not units or any(not isinstance(unit.get("value"), str) or (key and not unit["value"].strip()) for _, unit in units):
            widget_coverage_issues += 1
            widget_issue_items.append(key)

    widget_source_roots = [
        Path("OffshoreBudgetingWidgets"),
        Path("OffshoreBudgeting/WidgetSnapshotBuilders"),
    ]
    for source_path, source_text in extract_widget_source_strings(widget_source_roots):
        entry = widget_strings.get(source_text)
        if entry is None:
            source_coverage_issues += 1
            source_issue_items.append(
                f"{source_path} missing widget catalog key for {source_text!r}"
            )
else:
    widget_coverage_issues += 1
    widget_issue_items.append("missing OffshoreBudgetingWidgets/Localizable.xcstrings")

if target_locale in plist_supported_locales:
    plist_targets: list[tuple[Path, set[str]]] = []
    if catalog_path == app_catalog_path:
        plist_targets.append((Path(f"OffshoreBudgeting/{target_locale}.lproj/InfoPlist.strings"), app_plist_required_keys))
        plist_targets.append((Path(f"OffshoreBudgetingWidgets/{target_locale}.lproj/InfoPlist.strings"), widget_plist_required_keys))
    elif catalog_path == widget_catalog_path:
        plist_targets.append((Path(f"OffshoreBudgetingWidgets/{target_locale}.lproj/InfoPlist.strings"), widget_plist_required_keys))

    for plist_path, required_keys in plist_targets:
        parsed = parse_strings_file(plist_path)
        if not plist_path.exists():
            plist_coverage_issues += 1
            plist_issue_items.append(f"missing {plist_path}")
            continue

        for required_key in sorted(required_keys):
            value = parsed.get(required_key, "")
            if not isinstance(value, str) or not value.strip():
                plist_coverage_issues += 1
                plist_issue_items.append(f"{plist_path} missing {required_key}")

if catalog_path == app_catalog_path:
    for source_text in extract_generated_help_strings(generated_help_path):
        entry = strings.get(source_text)
        if entry is None:
            source_coverage_issues += 1
            source_issue_items.append(
                f"{generated_help_path} missing catalog key for {source_text!r}"
            )

    for source_text in extract_release_log_strings(release_logs_path):
        entry = strings.get(source_text)
        if entry is None:
            source_coverage_issues += 1
            source_issue_items.append(
                f"{release_logs_path} missing catalog key for {source_text!r}"
            )

    for source_text in extract_about_strings(about_view_path):
        entry = strings.get(source_text)
        if entry is None:
            source_coverage_issues += 1
            source_issue_items.append(
                f"{about_view_path} missing catalog key for {source_text!r}"
            )

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
    "OffshoreBudgeting/CoreViews/Cards/CardDetailView.swift": [
        'Text("Date ↑").tag(SortMode.dateAsc)',
        'Text("Date ↓").tag(SortMode.dateDesc)',
    ],
    "OffshoreBudgeting/CoreViews/Cards/CardVisualView.swift": [
        'case .plastic: return "Plastic"',
        'case .metal: return "Metal"',
        'case .holographic: return "Holographic"',
        'case .glass: return "Glass"',
        'rawValue.prefix(1).uppercased() + rawValue.dropFirst()',
    ],
    "OffshoreBudgeting/CoreViews/Cards/AllocationAccountDetailView.swift": [
        'case .none: return "None"',
        'case .split: return "Split"',
        'case .offset: return "Offset"',
    ],
    "OffshoreBudgeting/CoreViews/Home/HomeView.swift": [
        'Text("Widgets")',
        'Text("Tap Edit to pin widgets and cards to Home.")',
        'title: "Next Planned Expense"',
    ],
    "OffshoreBudgeting/CoreViews/SharedViewComponents/DateRangeFilterRow.swift": [
        'PillDatePickerField(title: "Start Date", date: $draftStartDate)',
        'PillDatePickerField(title: "End Date", date: $draftEndDate)',
        '.accessibilityLabel("Apply Date Range")',
        '.accessibilityLabel("Quick Date Ranges")',
    ],
    "OffshoreBudgeting/CoreViews/Income/SavingsAccountView.swift": [
        'case runningTotal = "Running Total"',
        'case currentPeriod = "Current Period"',
        'Text(mode.rawValue).tag(mode)',
        'Text("Running Total")',
        'Text("Savings Trend")',
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
    "OffshoreBudgeting/CoreViews/Settings/Presets/ManagePresetsView.swift": [
        'Section("Next Planned Expense")',
        'sortMenuButton(title: "A–Z", mode: .az)',
        'sortMenuButton(title: "Z–A", mode: .za)',
        'sortMenuButton(title: "Date ↑", mode: .dateAsc)',
        'sortMenuButton(title: "Date ↓", mode: .dateDesc)',
        '.accessibilityLabel("Sort")',
    ],
    "OffshoreBudgeting/AppCommands.swift": [
        'title: "Sort A-Z"',
        'title: "Sort Z-A"',
        'title: "Sort Date ↑"',
        'title: "Sort Date ↓"',
        'title: "Sort $↑"',
        'title: "Sort $↓"',
    ],
    "OffshoreBudgeting/CoreViews/Settings/SettingsGeneralView.swift": [
        'private func maintenanceButton(title: String, tint: Color, action: @escaping () -> Void)',
    ],
    "OffshoreBudgeting/CoreViews/Settings/SettingsPrivacyView.swift": [
        'private func permissionRow(title: String, status: String, description: String)',
    ],
    "OffshoreBudgeting/EditEntityViews/EditPlannedExpenseView.swift": [
        'case .split: return "Split"',
        'case .offset: return "Offset"',
    ],
    "OffshoreBudgeting/FormViews/ExpenseFormView.swift": [
        'case .split: return "Split"',
        'case .offset: return "Offset"',
    ],
    "OffshoreBudgetingWidgets/NextPlannedExpense/NextPlannedExpenseWidgetEntryView.swift": [
        'title: "Next Planned Expense"',
    ],
    "OffshoreBudgetingWidgets/NextPlannedExpense/NextPlannedExpenseWidgetViews.swift": [
        'title: snapshot.title',
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
print(f"locale: {target_locale}")
print(f"{target_locale} missing: {missing_count}")
print(f"{target_locale} equals key (non-allowlisted): {equals_key_count}")
print(f"{target_locale} equals en (non-allowlisted): {equals_en_count}")
print(f"placeholder mismatches: {placeholder_mismatches}")
print(f"translation state issues: {review_issues}")
print(f"glossary issues: {glossary_issues}")
print(f"widget coverage issues: {widget_coverage_issues}")
print(f"plist coverage issues: {plist_coverage_issues}")
print(f"source coverage issues: {source_coverage_issues}")

if missing_items:
    print(f"\nMissing {target_locale} items:")
    for item in missing_items[:50]:
        print(f"- {item}")

if equals_key_items:
    print(f"\nTop {target_locale}==key items:")
    for item in equals_key_items[:20]:
        print(f"- {item}")

if equals_en_items:
    print(f"\nTop {target_locale}==en items:")
    for item in equals_en_items[:20]:
        print(f"- {item}")

if placeholder_mismatch_items:
    print("\nTop placeholder mismatch items:")
    for item in placeholder_mismatch_items[:20]:
        print(f"- {item}")

if review_issue_items:
    print("\nTranslations needing review:")
    for item in review_issue_items[:20]:
        print(f"- {item}")

if glossary_issue_items:
    print("\nGlossary issues:")
    for item in glossary_issue_items[:20]:
        print(f"- {item}")

if widget_issue_items:
    print("\nWidget coverage issues:")
    for item in widget_issue_items[:20]:
        print(f"- {item}")

if plist_issue_items:
    print("\nPlist coverage issues:")
    for item in plist_issue_items[:20]:
        print(f"- {item}")

if source_issue_items:
    print("\nSource coverage issues:")
    for item in source_issue_items[:20]:
        print(f"- {item}")

if (
    missing_count > 0
    or equals_key_count > 0
    or equals_en_count > 0
    or placeholder_mismatches > 0
    or review_issues > 0
    or glossary_issues > 0
    or widget_coverage_issues > 0
    or plist_coverage_issues > 0
    or source_coverage_issues > 0
):
    sys.exit(1)
PY
}

status=0
for CATALOG_PATH in "${CATALOG_PATHS[@]}"; do
  if [[ ! -f "$CATALOG_PATH" ]]; then
    echo "error: catalog not found at '$CATALOG_PATH'" >&2
    exit 2
  fi
  if [[ -n "$TARGET_LOCALE" ]]; then
    locales=("$TARGET_LOCALE")
  else
    # Keep supported languages in sync with the Xcode project, including newly added ones.
    locales=()
    locale_list="$(python3 - <<'PYLOCALES'
import plistlib
import subprocess
project = plistlib.loads(subprocess.check_output([
    "plutil", "-convert", "xml1", "-o", "-", "OffshoreBudgeting.xcodeproj/project.pbxproj"
]))
settings = project["objects"][project["rootObject"]]
for locale in settings["knownRegions"]:
    if locale not in {"Base", settings.get("developmentRegion", "en")}:
        print(locale)
PYLOCALES
)" || exit 2
    while IFS= read -r locale; do
      [[ -n "$locale" ]] && locales+=("$locale")
    done <<< "$locale_list"
    if [[ ${#locales[@]} -eq 0 ]]; then
      echo "error: no target languages found in Xcode project" >&2
      exit 2
    fi
  fi
  for locale in "${locales[@]}"; do
    run_audit "$locale" || status=1
    echo
  done
done
exit "$status"
