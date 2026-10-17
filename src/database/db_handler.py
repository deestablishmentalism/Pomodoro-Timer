import sqlite3
from pathlib import Path
from platformdirs import user_data_dir
class Db_Handler():
    def __init__(self):
        self._init_table()
    def _init_db(self):
        data_dir = Path(user_data_dir("PomodoroTimer"))
        data_dir.mkdir(parents=True, exist_ok=True)
        database_path = data_dir / "app.db"
        if not database_path.exists():
            database_path.touch()
        return database_path
    def _init_table(self):
        try: 
            conn_path = self._init_db()
            conn = sqlite3.connect(conn_path)
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS timer_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    work_duration INTEGER NOT NULL,
                    rest_duration INTEGER NOT NULL,
                    cycles INTEGER NOT NULL,
                    rest_media_directory TEXT
                )
            ''')
            conn.commit()
            conn.close()
        except sqlite3.Error as e:
            raise Exception(f"Failed to create table: {e}")
    def insert_timer_history(self, work_duration, rest_duration, cycles, rest_media_directory):
        try:
            conn_path = self._init_db()
            conn = sqlite3.connect(conn_path)
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO timer_history (work_duration, rest_duration, cycles, rest_media_directory)
                VALUES (?, ?, ?, ?)
            ''', (work_duration, rest_duration, cycles, rest_media_directory))
            conn.commit()
            conn.close()
        except sqlite3.Error as e:
            raise Exception(f"Failed to insert timer history: {e}")
        except Exception as e:
            raise Exception(f"An unexpected error occurred: {e}")
    def get_timer_history(self):
        try:
            conn_path = self._init_db()
            conn = sqlite3.connect(conn_path)
            cursor = conn.cursor()
            cursor.execute('''
                SELECT id, work_duration, rest_duration, cycles, rest_media_directory
                FROM timer_history
                ORDER BY id DESC
            ''')
            rows = cursor.fetchall()
            conn.close()
            return rows
        except sqlite3.Error as e:
            raise Exception(f"Failed to fetch timer history: {e}")
    def delete_timer_history(self, record_id):
        try:
            conn_path = self._init_db()
            conn = sqlite3.connect(conn_path)
            cursor = conn.cursor()
            cursor.execute('DELETE FROM timer_history WHERE id = ?', (record_id,))
            conn.commit()
            conn.close()
        except sqlite3.Error as e:
            raise Exception(f"Failed to delete timer history: {e}")