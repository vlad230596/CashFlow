"""Complete semantic diff of normalized MCC snapshots, without persistence."""


def snapshot_diff(previous, proposed):
    previous = previous or {}
    changed_fields = sorted(
        key
        for key in set(previous) | set(proposed)
        if key != "categories" and previous.get(key) != proposed.get(key)
    )
    old = {item["sourceKey"]: item for item in previous.get("categories", [])}
    new = {item["sourceKey"]: item for item in proposed.get("categories", [])}
    categories = []
    for key in sorted(set(old) | set(new)):
        before, after = old.get(key), new.get(key)
        fields = sorted(
            field
            for field in set(before or {}) | set(after or {})
            if (before or {}).get(field) != (after or {}).get(field)
        )
        status = (
            "added"
            if before is None
            else "removed"
            if after is None
            else "changed"
            if fields
            else "unchanged"
        )
        categories.append({"source_key": key, "status": status, "changed_fields": fields})
    return {"changed_fields": changed_fields, "categories": categories}
