"""Process-local reference audio cache keyed by SHA-256.

VoStory can send only the digest on later requests so the same voice is not
re-uploaded over the WAN between consecutive sentences.
"""

from __future__ import annotations

import hashlib
import shutil
import tempfile
import threading
from collections import OrderedDict
from pathlib import Path

MAX_ITEMS = 32


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


class RefAudioCache:
    def __init__(self, max_items: int = MAX_ITEMS) -> None:
        self.max_items = max_items
        self._lock = threading.Lock()
        self._dir = Path(tempfile.mkdtemp(prefix="breeze_ref_cache_"))
        self._items: OrderedDict[str, Path] = OrderedDict()

    def get(self, digest: str) -> Path | None:
        key = digest.strip().lower()
        if not key:
            return None
        with self._lock:
            path = self._items.get(key)
            if path is None or not path.is_file():
                if key in self._items:
                    del self._items[key]
                return None
            self._items.move_to_end(key)
            return path

    def put(self, digest: str, source: Path) -> Path:
        key = digest.strip().lower()
        dest = self._dir / key
        if dest.resolve() != source.resolve():
            shutil.copy2(source, dest)
        with self._lock:
            self._items[key] = dest
            self._items.move_to_end(key)
            while len(self._items) > self.max_items:
                _, old = self._items.popitem(last=False)
                if old.resolve() != dest.resolve():
                    old.unlink(missing_ok=True)
        return dest


_cache = RefAudioCache()
