"""Run the successor contract and fixture foundation checks.

Usage: python3 tests/run_contracts.py
"""

import copy
import json
import pathlib
import re
import sys
import unittest

from contract_schema import canonical_trace, validate, validate_trace, POSITIONS


ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def source_inventory(path):
    """Count commands and branch/join arms in the five legacy reference files."""
    source = "\n".join(line.split("%", 1)[0] for line in path.read_text(encoding="utf-8").splitlines())
    counts = {kind: len(re.findall(r"\\" + kind + r"(?:\[[^]]*\])?\{", source))
              for kind in ("start", "function", "finish", "flow", "loopflow", "structure", "precondition", "timing", "note")}
    for command in ("branch", "join"):
        counts[command + "_logics"] = re.findall(r"\\" + command + r"\[(and|or)\]", source)
        counts[command + "_arms"] = 0
        for match in re.finditer(r"\\" + command + r"(?:\[[^]]*\])?\{", source):
            start = match.end()
            depth = 1
            end = start
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            if command == "branch":
                start = end + 1
                depth = 1
                end = start
                while depth:
                    depth += (source[end] == "{") - (source[end] == "}")
                    end += 1
            else:
                start = match.end()
            arms = source[start:end - 1]
            counts[command + "_arms"] += arms.count(",") + 1
    return counts


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.simple = load(FIXTURES / "scenes" / "valid-simple.json")

    def test_valid_mock_scenes_and_stable_serialization(self):
        for filename in ("valid-simple.json", "valid-multipage.json"):
            trace = load(FIXTURES / "scenes" / filename)
            self.assertEqual(validate_trace(trace), [], filename)
            serialized = canonical_trace(trace)
            self.assertEqual(serialized, canonical_trace(json.loads(serialized)))

    def test_invalid_mock_scene(self):
        trace = load(FIXTURES / "scenes" / "invalid-malformed.json")
        errors = validate_trace(trace)
        self.assertTrue(any("scale" in error for error in errors), errors)
        self.assertTrue(any("integer sp" in error for error in errors), errors)
        self.assertTrue(any("orthogonal" in error for error in errors), errors)

    def test_required_fields_and_type(self):
        scene = self.simple["objects"]["Scene"]
        del scene["pages"]
        self.assertTrue(any("Scene.pages: required" in e for e in validate("Scene", scene)))
        self.assertTrue(validate("Frame", {"environment_id": "x"}))
        self.assertTrue(validate("Diagnostic", {"code": "x"}))

    def test_environment_isolation(self):
        trace = copy.deepcopy(self.simple)
        trace["objects"]["Scene"]["environment_id"] = "another-environment"
        self.assertTrue(any("environment mismatch" in e for e in validate_trace(trace)))

    def test_ids_and_duplicate_indices(self):
        spec = {
            "environment_id": "id-test",
            "nodes": [
                {"id": "a", "index": 1, "kind": "start", "text_ref": "@text/1"},
                {"id": "b", "index": 2, "kind": "finish", "text_ref": "@text/2"}],
            "flows": [{"id": "@flow/3", "index": 3, "source": "a", "target": "b", "kind": "forward"}],
            "branches": [], "joins": [], "structures": [], "annotations": [],
            "constraints": [], "options": {"direction": "right", "scale": 1, "multipage": False},
        }
        self.assertEqual(validate("Spec", spec), [])
        connector = copy.deepcopy(spec)
        connector["nodes"].append({"id": "@branch/4", "index": 4, "kind": "split", "logic": "or"})
        connector["flows"].append({"id": "@flow/5", "index": 4, "source": "a", "target": "@branch/4", "kind": "forward"})
        connector["flows"].append({"id": "@flow/6", "index": 4, "source": "@branch/4", "target": "b", "kind": "forward"})
        connector["branches"].append({"connector_id": "@branch/4", "source_id": "a", "arm_flow_ids_in_user_order": ["@flow/6"]})
        self.assertEqual(validate("Spec", connector), [])
        bad = copy.deepcopy(spec)
        bad["nodes"][1]["id"] = "@flow/3"
        bad["nodes"][1]["index"] = 1
        bad["flows"][0]["target"] = "missing"
        errors = validate("Spec", bad)
        self.assertTrue(any("invalid user ID" in e for e in errors), errors)
        self.assertTrue(any("duplicate declaration index" in e for e in errors), errors)
        self.assertTrue(any("unknown node" in e for e in errors), errors)
        bad["nodes"][0]["id"] = ["not-an-id"]
        bad["flows"][0]["target"] = {"bad": "reference"}
        self.assertTrue(validate("Spec", bad))

    def test_nonfinite_geometry_and_annotation_position(self):
        trace = copy.deepcopy(self.simple)
        scene = trace["objects"]["Scene"]
        scene["scale"] = float("inf")
        scene["pages"][0]["annotations"][0]["position"] = "center"
        errors = validate_trace(trace)
        self.assertTrue(any("finite" in e for e in errors), errors)
        self.assertTrue(any("position" in e for e in errors), errors)

    def test_continuation_links(self):
        trace = load(FIXTURES / "scenes" / "valid-multipage.json")
        trace["objects"]["Scene"]["pages"][1]["continuation_markers"][0]["counterpart_id"] = "@continuation/missing"
        self.assertTrue(any("reciprocal counterpart" in e for e in validate_trace(trace)))

    def test_all_phase_shapes(self):
        rect = {"x_sp": 0, "y_sp": 0, "width_sp": 100, "height_sp": 50}
        samples = {
            "Metrics": {"environment_id": "e", "by_text_ref": {"@text/1": {"width_sp": 10, "height_sp": 5, "depth_sp": 0}}, "by_node_id": {"a": {"width_sp": 100, "height_sp": 50}}, "by_annotation_id": {}, "by_structure_id": {}, "style_clearances": {"edge_sp": 5}},
            "Frame": {"environment_id": "e", "page_width_sp": 1000, "page_height_sp": 1000, "content_width_sp": 900, "content_height_sp": 900, "direction": "right", "scale": 1},
            "Constraint": {"id": "@constraint/1", "kind": "max-columns", "target_ids": [], "value": 5, "strength": "hard", "source": {"command": "ffbd", "declaration_index": 1}},
            "Diagnostic": {"code": "test-warning", "severity": "warning", "object_ids": [], "constraint_ids": [], "message": "Example", "suggested_actions": []},
            "Regions": {"environment_id": "e", "root": "@region/1", "regions_by_id": {"@region/1": {"id": "@region/1", "kind": "sequence", "ordered_children": [], "member_ids": ["a"], "can_keep_together": True}}, "fallback_subgraphs": [], "ambiguities": []},
            "Plan": {"environment_id": "e", "pages": [{"rows": [{"index": 0, "direction_sign": 1, "ordered_region_ids": ["@region/1"], "ordered_node_ids": ["a"], "forced_break_ids": []}], "continuation_ids": []}], "estimated_costs": {}},
            "Geometry": {"environment_id": "e", "node_rects_by_id": {"a": rect}, "group_rects_by_id": {}, "row_axes": [], "reserved_channels": [], "provisional_ports": [], "spacing_stats": {}},
            "Routes": {"environment_id": "e", "paths_by_flow_id": {}, "ports_by_id": {}, "shared_trunks": [], "crossings": [], "congestion": [], "costs": {}, "conflicts": []},
        }
        for kind, sample in samples.items():
            with self.subTest(kind=kind):
                self.assertEqual(validate(kind, sample), [])
        samples["Metrics"]["by_node_id"]["a"]["width_sp"] = True
        self.assertTrue(any("integer sp" in e for e in validate("Metrics", samples["Metrics"])))

    def test_fixture_manifest(self):
        manifest = load(FIXTURES / "manifest.json")
        self.assertEqual(manifest["manifest_version"], 1)
        fixtures = manifest["fixtures"]
        self.assertIn("standard", manifest["geometry_check_profiles"])
        ids = [f["id"] for f in fixtures]
        self.assertEqual(len(ids), len(set(ids)))
        categories = {f["category"] for f in fixtures}
        self.assertTrue({"simple", "dense", "wrapped", "structured", "annotated", "multipage", "invalid-constraint"} <= categories)
        self.assertTrue(any(f["blocks"] > 50 and f["semantic"].get("multipage") is True for f in fixtures))
        self.assertTrue(any(f["blocks"] > 50 and f["semantic"].get("multipage") is False for f in fixtures))
        self.assertEqual(set(next(f for f in fixtures if f["id"] == "annotations-eight")["semantic"]["annotation_positions"]), POSITIONS)
        for fixture in fixtures:
            with self.subTest(fixture=fixture["id"]):
                self.assertRegex(fixture["id"], r"^[a-z][a-z0-9-]+$")
                self.assertIn(fixture["direction"], ("right", "down"))
                self.assertGreater(fixture["blocks"], 0)
                self.assertTrue(fixture["semantic"])
                self.assertTrue(fixture["visual_prompt"])
                self.assertIn(fixture["geometry_check_profile"], manifest["geometry_check_profiles"])
                self.assertEqual(set(fixture["visual_review"]), {"reference", "rating", "notes"})
                if fixture["status"] == "source":
                    self.assertTrue((ROOT / fixture["source"]).is_file())
                    actual = source_inventory(ROOT / fixture["source"])
                    semantic = fixture["semantic"]
                    self.assertEqual(fixture["blocks"], actual["start"] + actual["function"] + actual["finish"])
                    self.assertEqual(semantic["starts"], actual["start"])
                    self.assertEqual(semantic["finishes"], actual["finish"])
                    self.assertEqual(semantic["forward_flows"], actual["flow"] + actual["branch_arms"] + actual["join_arms"])
                    self.assertEqual(semantic["feedback_flows"], actual["loopflow"])
                    self.assertEqual(semantic["structures"], actual["structure"])
                    self.assertEqual(semantic["annotations"], actual["precondition"] + actual["timing"] + actual["note"])
                    self.assertEqual(semantic["split_logics"], actual["branch_logics"])
                    self.assertEqual(semantic["join_logics"], actual["join_logics"])
                else:
                    self.assertIsNone(fixture["source"])


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
