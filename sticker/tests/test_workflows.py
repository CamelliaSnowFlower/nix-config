"""Structural checks for the exported n8n workflows.

These cannot prove the workflows run in n8n (that needs a real n8n instance and
a test submission). They catch the mistakes that are easy to make when editing
the JSON by hand or re-exporting it: broken connections, commands that no
longer match sticker-tool's arguments, form labels that drifted from the code
that reads them, and anything that looks like a stored secret.

Run from the repository root:

    python3 -m unittest discover -s sticker/tests -v
"""

import json
import re
import shlex
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import sticker_tool as st  # noqa: E402

N8N = ROOT / "n8n"
SAMPLE_VALUES = {
    "$execution.id": "1234",
    "$execution.resumeFormUrl": "https://uranus.example.ts.net/form-waiting/1234?signature=abc",
    "$json.job_id": "job_0123456789ab",
    "$json.profile": "default",
    "$('Parse intake').first().json.job_id": "job_0123456789ab",
    "$json.execution.id": "1234",
    "$json.execution.lastNodeExecuted": "Process stickers",
}


def load(name):
    return json.loads((N8N / name).read_text())


def expand(command):
    """Replace each {{ expression }} with a sample value, rejecting unknown ones."""
    def substitute(match):
        expression = match.group(1).strip()
        if expression not in SAMPLE_VALUES:
            raise AssertionError(f"expression not on the allow-list: {expression!r}")
        return SAMPLE_VALUES[expression]

    return re.sub(r"\{\{(.*?)\}\}", substitute, command.lstrip("="))


class WorkflowStructureTests(unittest.TestCase):
    WORKFLOWS = ("sticker-job.workflow.json", "sticker-error.workflow.json")

    def test_files_are_valid_and_connections_resolve(self):
        for name in self.WORKFLOWS:
            wf = load(name)
            names = [n["name"] for n in wf["nodes"]]
            self.assertEqual(len(names), len(set(names)), f"{name}: duplicate node names")
            ids = [n["id"] for n in wf["nodes"]]
            self.assertEqual(len(ids), len(set(ids)))
            for source, outputs in wf["connections"].items():
                self.assertIn(source, names)
                for branch in outputs["main"]:
                    for target in branch:
                        self.assertIn(target["node"], names, f"{name}: dangling connection")
            self.assertFalse(wf["active"], "exports must not auto-activate on import")

    def test_every_working_node_is_reachable_from_the_trigger(self):
        for name in self.WORKFLOWS:
            wf = load(name)
            triggers = [n["name"] for n in wf["nodes"] if n["type"].endswith(("formTrigger", "errorTrigger"))]
            self.assertEqual(len(triggers), 1)
            seen, queue = set(), list(triggers)
            while queue:
                current = queue.pop()
                if current in seen:
                    continue
                seen.add(current)
                for branch in wf["connections"].get(current, {}).get("main", []):
                    queue.extend(t["node"] for t in branch)
            expected = {n["name"] for n in wf["nodes"] if not n["type"].endswith("stickyNote")}
            self.assertEqual(seen, expected, f"{name}: unreachable nodes")

    def test_commands_match_the_sticker_tool_command_line(self):
        parser = st.build_parser()
        seen = set()
        for name in self.WORKFLOWS:
            for node in load(name)["nodes"]:
                if not node["type"].endswith("executeCommand"):
                    continue
                self.assertTrue(node.get("executeOnce"), f"{node['name']}: must run once per execution")
                command = node["parameters"]["command"]
                self.assertTrue(command.lstrip("=").startswith("sticker-tool "), node["name"])
                for forbidden in (";", "&&", "||", "|", "`", "$(", ">", "<"):
                    self.assertNotIn(forbidden, re.sub(r"\{\{.*?\}\}", "", command), f"{node['name']}: {forbidden!r}")
                tokens = shlex.split(expand(command))[1:]
                args = parser.parse_args(tokens)
                seen.add(args.command)
        self.assertTrue({"mkincoming", "intake", "process", "nest", "note-approval", "commit", "reject"} <= seen)
        self.assertIn("record-error", seen)

    def test_form_labels_used_by_code_exist_in_the_form(self):
        wf = load("sticker-job.workflow.json")
        form = next(n for n in wf["nodes"] if n["type"].endswith("formTrigger"))
        labels = {f["fieldLabel"] for f in form["parameters"]["formFields"]["values"]}
        prepare = next(n for n in wf["nodes"] if n["name"] == "Prepare files")
        used = set(re.findall(r"form\.json\['([^']+)'\]", prepare["parameters"]["jsCode"]))
        self.assertTrue(used)
        self.assertLessEqual(used, labels)
        sheet_options = {
            o["option"]
            for f in form["parameters"]["formFields"]["values"]
            if f["fieldLabel"] == "Sheet types"
            for o in f["fieldOptions"]["values"]
        }
        self.assertEqual(sheet_options, set(st.DEFAULT_CONFIG["sheets"]))

    def test_approval_choices_and_profiles_line_up(self):
        wf = load("sticker-job.workflow.json")
        wait = next(n for n in wf["nodes"] if n["type"].endswith(".wait"))
        options = [o["option"] for o in wait["parameters"]["formFields"]["values"][0]["fieldOptions"]["values"]]
        switch = next(n for n in wf["nodes"] if n["type"].endswith(".switch"))
        rules = [r["conditions"]["conditions"][0]["rightValue"] for r in switch["parameters"]["rules"]["values"]]
        self.assertEqual(options, rules)
        self.assertEqual(len(wf["connections"]["Decision"]["main"]), len(rules))
        choose = next(n for n in wf["nodes"] if n["name"] == "Choose profile")
        mapped = set(re.findall(r"'(wide-gap|more-rotations)'", choose["parameters"]["jsCode"]))
        self.assertLessEqual(mapped, set(st.DEFAULT_CONFIG["profiles"]))
        for label in re.findall(r"'(Re-run[^']+)'", choose["parameters"]["jsCode"]):
            self.assertIn(label, options)

    def test_webhook_nodes_have_ids_and_no_secrets_are_stored(self):
        for name in self.WORKFLOWS:
            wf = load(name)
            for node in wf["nodes"]:
                if node["type"].endswith(("formTrigger", ".wait")):
                    self.assertTrue(node.get("webhookId"), node["name"])
                self.assertNotIn("credentials", node, f"{node['name']}: exports must not embed credentials")
            text = (N8N / name).read_text().lower()
            for word in ("password", "apikey", "api_key", "secret", "bearer ", "begin private key"):
                self.assertNotIn(word, text)


if __name__ == "__main__":
    unittest.main()
