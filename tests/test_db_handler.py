import contextlib
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Make src/ importable when running unittest from the repository root
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from database.db_handler import Db_Handler


class TestDbHandler(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.data_dir = Path(self._tmpdir.name) / "pomodoro_test_data"
        self.patcher = patch("database.db_handler.user_data_dir", return_value=str(self.data_dir))
        self.mock_user_data_dir = self.patcher.start()

    def tearDown(self):
        self.patcher.stop()
        self._tmpdir.cleanup()

    def test_database_creation_and_existing_db_pass(self):
        db_file = self.data_dir / "app.db"
        self.assertFalse(db_file.exists(), "Database file should not exist before Db_Handler initialization")

        # First run: creates the database file and timer_history table
        handler = Db_Handler()
        self.assertTrue(db_file.is_file(), "Database file should be created on initialization")

        with contextlib.closing(sqlite3.connect(db_file)) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='timer_history'"
            )
            table = cursor.fetchone()
            self.assertIsNotNone(table, "timer_history table should exist in the created database")

        # Second run: when database file already exists, initialization should pass without error
        handler_existing = Db_Handler()
        self.assertIsNotNone(handler_existing)
        self.assertTrue(db_file.is_file())

    def test_insert_timer_history(self):
        db_file = self.data_dir / "app.db"
        handler = Db_Handler()

        handler.insert_timer_history(
            work_duration=25,
            rest_duration=5,
            cycles=4,
            rest_media_directory="/mock/path/to/media",
        )
        handler.insert_timer_history(
            work_duration=50,
            rest_duration=10,
            cycles=2,
            rest_media_directory=None,
        )

        with contextlib.closing(sqlite3.connect(db_file)) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT work_duration, rest_duration, cycles, rest_media_directory "
                "FROM timer_history ORDER BY id ASC"
            )
            rows = cursor.fetchall()

        self.assertEqual(
            rows,
            [
                (25, 5, 4, "/mock/path/to/media"),
                (50, 10, 2, None),
            ],
        )

    def test_get_and_delete_timer_history(self):
        handler = Db_Handler()
        handler.insert_timer_history(25, 5, 4, "/mock/path/1")
        handler.insert_timer_history(50, 10, 2, None)

        history = handler.get_timer_history()
        self.assertEqual(len(history), 2)
        first_id = history[0][0]
        second_id = history[1][0]

        handler.delete_timer_history(first_id)
        remaining = handler.get_timer_history()
        self.assertEqual(len(remaining), 1)
        self.assertEqual(remaining[0], (second_id, 25, 5, 4, "/mock/path/1"))


if __name__ == "__main__":
    unittest.main()

