from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any
from uuid import UUID

from comfy_bridge.domain.models import AgentEvent, TaskSnapshot


class EventBus:
    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue[AgentEvent]] = set()
        self._sequence = 0
        self._lock = asyncio.Lock()

    async def publish_task(
        self,
        event_type: str,
        task: TaskSnapshot,
    ) -> None:
        await self.publish(event_type, task.id, task.model_dump(by_alias=True, mode="json"))

    async def publish(
        self,
        event_type: str,
        task_id: UUID | None,
        payload: dict[str, Any],
    ) -> None:
        async with self._lock:
            self._sequence += 1
            event = AgentEvent(
                sequence=self._sequence,
                type=event_type,  # type: ignore[arg-type]
                task_id=task_id,
                payload=payload,
            )
            subscribers = tuple(self._subscribers)
        for queue in subscribers:
            if queue.full():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            queue.put_nowait(event)

    @asynccontextmanager
    async def subscribe(self) -> AsyncIterator[asyncio.Queue[AgentEvent]]:
        queue: asyncio.Queue[AgentEvent] = asyncio.Queue(maxsize=100)
        async with self._lock:
            self._subscribers.add(queue)
        try:
            yield queue
        finally:
            async with self._lock:
                self._subscribers.discard(queue)
