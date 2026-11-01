"""Regression checks for the audit CLI; run with python3 -m unittest discover -s Scripts."""

import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name("localization_audit.sh")


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


class LocalizationAuditTests(unittest.TestCase):
    def audit(self, strings, locale="es", source_language="en"):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / "Localizable.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": source_language,
                "strings": strings,
                "version": "1.0",
            }), encoding="utf-8")
            # An absolute catalog outside the repo also exercises invocation from another cwd.
            return subprocess.run(
                ["bash", str(SCRIPT), str(catalog), locale],
                cwd=directory, capture_output=True, text=True, check=False,
            )

    def entry(self, source, target, state="translated"):
        return {"localizations": {"en": unit(source), "es": unit(target, state)}}

    def assert_passes(self, strings):
        result = self.audit(strings)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_positional_reordering_preserves_argument_types(self):
        self.assert_passes({"Summary": self.entry(
            "%1$@ has %2$lld items costing %3$.2f",
            "%2$lld artículos de %1$@ cuestan %3$.2f",
        )})

    def test_lost_positional_fields_fail(self):
        result = self.audit({"Summary": self.entry(
            "%1$@. Date %2$@. Planned %3$@. Actual %4$@.", "Próximo gasto.",
        )})
        self.assertEqual(result.returncode, 1)
        self.assertIn("placeholder mismatches: 1", result.stdout)

    def test_length_precision_and_argument_positions_are_checked(self):
        for source, target in [
            ("%lld items", "%d artículos"),
            ("Value %.2f", "Valor"),
            ("%1$@ %2$lld", "%2$@ %1$lld"),
            ("Value %*.*f", "Valor %f"),
        ]:
            with self.subTest(source=source):
                result = self.audit({"Summary": self.entry(source, target)})
                self.assertEqual(result.returncode, 1)
                self.assertIn("placeholder mismatches: 1", result.stdout)

    def test_dynamic_precision_and_escaped_percent(self):
        self.assert_passes({"Summary": self.entry(
            "Value %*.*f %% done", "Valor %3$*1$.*2$f %% listo",
        )})
        self.assert_passes({"Summary": self.entry("Literal %%@", "Literal %%@ traducido")})

    def test_review_and_new_states_fail_even_when_values_exist(self):
        for state in ["needs_review", "new"]:
            with self.subTest(state=state):
                result = self.audit({"Summary": self.entry("Hello", "Hola", state)})
                self.assertEqual(result.returncode, 1)
                self.assertIn("translation state issues: 1", result.stdout)

    def test_blank_or_absent_translation_fails(self):
        for target in [unit(""), unit("  "), {}]:
            with self.subTest(target=target):
                result = self.audit({"Hello": {"localizations": {"es": target}}})
                self.assertEqual(result.returncode, 1)
                self.assertIn("es missing: 1", result.stdout)

    def test_dont_translate_and_empty_source_are_allowed(self):
        self.assert_passes({
            "Brand": {"shouldTranslate": False},
            "": {"localizations": {"es": unit("")}},
            "%@ – %@": {"localizations": {"es": unit("%@ – %@")}},
        })

    def test_spanish_glossary_uses_word_boundaries(self):
        for target in ["Un preset", "Dos preajustes"]:
            with self.subTest(target=target):
                result = self.audit({"Template": self.entry("A template", target)})
                self.assertEqual(result.returncode, 1)
                self.assertIn("glossary issues: 1", result.stdout)
        self.assert_passes({"Template": self.entry("A template", "Una plantilla")})

    def test_plural_units_and_additional_target_categories(self):
        self.assert_passes({"%lld items": {"localizations": {
            "en": {"variations": {"plural": {
                "one": unit("%lld item"), "other": unit("%lld items"),
            }}},
            "es": {"variations": {"plural": {
                "one": unit("%lld artículo"), "many": unit("%lld artículos"),
                "other": unit("%lld artículos"),
            }}},
        }}})
        result = self.audit({"%lld items": {"localizations": {
            "es": {"variations": {"plural": {"other": unit("Artículos")}}},
        }}})
        self.assertEqual(result.returncode, 1)
        self.assertIn("placeholder mismatches: 1", result.stdout)

    def test_catalog_source_language_is_used(self):
        result = self.audit({"greeting": {"localizations": {
            "fr": unit("Bonjour %@"), "es": unit("Hola %@"),
        }}}, source_language="fr")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_plural_other_branch_is_required(self):
        result = self.audit({"%lld items": {"localizations": {
            "en": {"variations": {"plural": {
                "one": unit("%lld item"), "other": unit("%lld items"),
            }}},
            "es": {"variations": {"plural": {"one": unit("%lld artículo")}}},
        }}})
        self.assertEqual(result.returncode, 1)
        self.assertIn("es missing: 1", result.stdout)
        self.assertIn("variations/plural/other", result.stdout)

    def test_named_substitution_cannot_be_dropped(self):
        result = self.audit({"Summary": self.entry(
            "There are %#@count@ items", "Hay artículos",
        )})
        self.assertEqual(result.returncode, 1)
        self.assertIn("placeholder mismatches: 1", result.stdout)

    def test_missing_catalog_has_error_status(self):
        result = subprocess.run(
            ["bash", str(SCRIPT), "/tmp/nonexistent-offshore-catalog.xcstrings"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("catalog not found", result.stderr)

    def test_default_command_checks_widget_formats_and_project_languages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "Scripts" / SCRIPT.name
            script.parent.mkdir()
            script.write_bytes(SCRIPT.read_bytes())
            project = root / "OffshoreBudgeting.xcodeproj" / "project.pbxproj"
            project.parent.mkdir()
            project.write_bytes(plistlib.dumps({
                "rootObject": "project",
                "objects": {"project": {
                    "knownRegions": ["Base", "en", "es"], "developmentRegion": "en",
                }},
            }))
            for target in ["OffshoreBudgeting", "OffshoreBudgetingWidgets"]:
                folder = root / target
                folder.mkdir()
                strings = {"Hello": self.entry("Hello", "Hola")}
                if target == "OffshoreBudgetingWidgets":
                    strings = {"Summary": self.entry("Value %lld", "Valor")}
                (folder / "Localizable.xcstrings").write_text(json.dumps({
                    "sourceLanguage": "en", "strings": strings, "version": "1.0",
                }))
                localized = folder / "es.lproj"
                localized.mkdir()
                (localized / "InfoPlist.strings").write_text("\n".join(
                    f'"{key}" = "Traducido";' for key in [
                        "CFBundleDisplayName", "NSFaceIDUsageDescription",
                        "NSLocationAlwaysAndWhenInUseUsageDescription",
                        "NSLocationWhenInUseUsageDescription", "NSPhotoLibraryUsageDescription",
                    ]
                ))
            result = subprocess.run(
                ["bash", str(script)], cwd="/tmp", capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count("locale: es\n"), 2)
            self.assertNotIn("locale: en\n", result.stdout)
            self.assertIn("placeholder mismatches: 1", result.stdout)


if __name__ == "__main__":
    unittest.main()
