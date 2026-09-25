from __future__ import annotations

import sqlite3
import threading
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID

from comfy_bridge.domain.models import TaskSnapshot


@dataclass(frozen=True, slots=True)
class AssetRecord:
    id: UUID
    path: Path
    original_name: str
    mime_type: str
    size: int


@dataclass(frozen=True, slots=True)
class MediaRecord:
    id: UUID
    task_id: UUID
    path: Path
    mime_type: str


class Store:
    def __init__(self, database_path: Path) -> None:
        database_path.parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(database_path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        self._migrate()

    def close(self) -> None:
        with self._lock:
            self._connection.close()

    def _migrate(self) -> None:
        with self._lock, self._connection:
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    client_request_id TEXT NOT NULL UNIQUE,
                    snapshot_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS tasks_created_at_idx
                    ON tasks(created_at DESC);

                CREATE TABLE IF NOT EXISTS assets (
                    id TEXT PRIMARY KEY,
                    path TEXT NOT NULL,
                    original_name TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    size INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS media (
                    id TEXT PRIMARY KEY,
                    task_id TEXT NOT NULL,
                    path TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    FOREIGN KEY(task_id) REFERENCES tasks(id)
                );
                """
            )

    def save_task(self, task: TaskSnapshot) -> None:
        payload = task.model_dump_json(by_alias=True)
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO tasks(id, client_request_id, snapshot_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    snapshot_json = excluded.snapshot_json,
                    updated_at = excluded.updated_at
                """,
                (
                    str(task.id),
                    str(task.client_request_id),
                    payload,
                    task.created_at.isoformat(),
                    task.updated_at.isoformat(),
                ),
            )

    def get_task(self, task_id: UUID) -> TaskSnapshot | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT snapshot_json FROM tasks WHERE id = ?", (str(task_id),)
            ).fetchone()
        return TaskSnapshot.model_validate_json(row["snapshot_json"]) if row else None

    def get_task_by_client_request(self, request_id: UUID) -> TaskSnapshot | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT snapshot_json FROM tasks WHERE client_request_id = ?",
                (str(request_id),),
            ).fetchone()
        return TaskSnapshot.model_validate_json(row["snapshot_json"]) if row else None

    def list_tasks(self, limit: int = 100) -> list[TaskSnapshot]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT snapshot_json FROM tasks ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
        return [TaskSnapshot.model_validate_json(row["snapshot_json"]) for row in rows]

    def save_asset(self, asset: AssetRecord) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                """
                INSERT INTO assets(id, path, original_name, mime_type, size)
                VALUES (?, ?, ?, ?, ?)
                """,
                (str(asset.id), str(asset.path), asset.original_name, asset.mime_type, asset.size),
            )

    def get_asset(self, asset_id: UUID) -> AssetRecord | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT * FROM assets WHERE id = ?", (str(asset_id),)
            ).fetchone()
        if not row:
            return None
        return AssetRecord(
            id=UUID(row["id"]),
            path=Path(row["path"]),
            original_name=row["original_name"],
            mime_type=row["mime_type"],
            size=row["size"],
        )

    def save_media(self, media: MediaRecord) -> None:
        with self._lock, self._connection:
            self._connection.execute(
                "INSERT INTO media(id, task_id, path, mime_type) VALUES (?, ?, ?, ?)",
                (str(media.id), str(media.task_id), str(media.path), media.mime_type),
            )

    def get_media(self, media_id: UUID) -> MediaRecord | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT * FROM media WHERE id = ?", (str(media_id),)
            ).fetchone()
        if not row:
            return None
        return MediaRecord(
            id=UUID(row["id"]),
            task_id=UUID(row["task_id"]),
            path=Path(row["path"]),
            mime_type=row["mime_type"],
        )

    def delete_media(self, media_id: UUID) -> None:
        with self._lock, self._connection:
            self._connection.execute("DELETE FROM media WHERE id = ?", (str(media_id),))

    def list_media_for_task(self, task_id: UUID) -> list[MediaRecord]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT * FROM media WHERE task_id = ?", (str(task_id),)
            ).fetchall()
        return [
            MediaRecord(
                id=UUID(row["id"]),
                task_id=UUID(row["task_id"]),
                path=Path(row["path"]),
                mime_type=row["mime_type"],
            )
            for row in rows
        ]

    def delete_task(self, task_id: UUID) -> None:
        with self._lock, self._connection:
            self._connection.execute("DELETE FROM media WHERE task_id = ?", (str(task_id),))
            self._connection.execute("DELETE FROM tasks WHERE id = ?", (str(task_id),))
