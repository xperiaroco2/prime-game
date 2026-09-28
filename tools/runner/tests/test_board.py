"""`board move`: finding the Status column in `gh project field-list` output."""

import unittest

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


if __name__ == "__main__":
    unittest.main()
