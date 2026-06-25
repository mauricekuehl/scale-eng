from collections import OrderedDict


class LRUCache:
    def __init__(self, capacity: int) -> None:
        self.capacity = capacity
        self.data: OrderedDict[str, str] = OrderedDict()
        self.hits = 0
        self.misses = 0

    def get(self, key: str) -> str | None:
        if key not in self.data:
            self.misses += 1
            return None
        # Move the accessed item to the end of the OrderedDict to mark it as recently used
        self.data.move_to_end(key)
        self.hits += 1
        return self.data[key]

    def put(self, key: str, value: str) -> None:
        if self.capacity <= 0:
            return  # If the capacity is zero or negative -> cache disabled
        self.data[key] = value
        self.data.move_to_end(key)
        if len(self.data) > self.capacity:
            # Remove the first item (the least recently used one)
            self.data.popitem(last=False)
