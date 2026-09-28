"""`board move`: finding the Status column in `gh project field-list` output."""

import unittest
from unittest import mock

from runner import board
from runner.common import Failure

# Shape of `gh project field-list 1 --owner xperiaroco2 --format json` (gh 2.101, 2026-09-29), trimmed.
FIELDS = {
    "fields": [
        {"id": "PVTF_title", "name": "Title", "type": "ProjectV2Field"},
        {
            "id": "PVTSSF_status",
            "name": "Status",
            "options": [
                {"id": "ee840767", "name": "Backlog"},
                {"id": "08f1a330", "name": "Ready"},
                {"id": "950e19f6", "name": "In progress"},
                {"id": "8537e708", "name": "In review"},
                {"id": "9e6aa3f3", "name": "Done"},
            ],
            "type": "ProjectV2SingleSelectField",
        },
    ],
    "totalCount": 2,
}


class StatusOptionTest(unittest.TestCase):
    def test_every_agent_move_has_a_column(self) -> None:
        self.assertEqual(board.status_option(FIELDS, board.MOVES["in-progress"]), ("PVTSSF_status", "950e19f6"))
        self.assertEqual(board.status_option(FIELDS, board.MOVES["in-review"]), ("PVTSSF_status", "8537e708"))

    def test_missing_column_names_the_existing_ones(self) -> None:
        with self.assertRaises(Failure) as caught:
            board.status_option(FIELDS, "Testing")
        self.assertIn("Backlog, Ready, In progress, In review, Done", str(caught.exception))

    def test_missing_status_field(self) -> None:
        with self.assertRaises(Failure):
            board.status_option({"fields": [FIELDS["fields"][0]]}, "In progress")

    def test_agents_only_set_two_columns(self) -> None:
        self.assertEqual(sorted(board.MOVES.values()), ["In progress", "In review"])


class MoveTest(unittest.TestCase):
    """move() with gh replaced by canned answers, keyed by the first two gh arguments."""

    def run_move(self, issue: dict[str, object]) -> list[tuple[str, ...]]:
        answers = {
            ("issue", "view"): issue,
            ("project", "view"): {"id": "PVT_1", "url": "https://github.com/users/x/projects/1"},
            ("project", "field-list"): FIELDS,
            ("project", "item-add"): {"id": "PVTI_7"},
            ("project", "item-edit"): {"id": "PVTI_7"},
        }
        calls: list[tuple[str, ...]] = []

        def fake_gh(*args: str) -> dict[str, object]:
            calls.append(args)
            return answers[args[:2]]  # type: ignore[return-value]

        with mock.patch.object(board, "_gh", side_effect=fake_gh), mock.patch.object(board, "ok"), mock.patch.object(
            board, "say"
        ):
            board.move(7, "in-review")
        return calls

    def test_sets_the_column_on_the_added_item(self) -> None:
        calls = self.run_move({"url": "https://github.com/o/r/issues/7", "state": "OPEN", "title": "t"})
        edit = next(c for c in calls if c[:2] == ("project", "item-edit"))
        for flag, value in (("--id", "PVTI_7"), ("--project-id", "PVT_1"), ("--single-select-option-id", "8537e708")):
            self.assertEqual(edit[edit.index(flag) + 1], value)

    def test_refuses_a_closed_issue_before_touching_the_board(self) -> None:
        with self.assertRaises(Failure) as caught:
            self.run_move({"url": "https://github.com/o/r/issues/7", "state": "CLOSED", "title": "t"})
        self.assertIn("CLOSED", str(caught.exception))

    def test_refuses_a_pull_request(self) -> None:
        with self.assertRaises(Failure) as caught:
            self.run_move({"url": "https://github.com/o/r/pull/7", "state": "OPEN", "title": "t"})
        self.assertIn("pull request", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
