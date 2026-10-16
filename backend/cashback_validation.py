"""Validation at the manual cashback API boundary, independent of ORM state."""

import math
from datetime import datetime

from business_time import MOSCOW

CATEGORY_TYPES = {"standard", "stackable_bonus", "task_bonus"}


def calendar_datetime(value):
    """Store cashback periods as Moscow wall time, matching imported periods."""
    if not isinstance(value, str):
        raise ValueError("Invalid date format. Use ISO format")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("Invalid date format. Use ISO format") from error
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(MOSCOW).replace(tzinfo=None)
    return parsed


def validate_cashback_payload(data, current=None):
    """Return normalized changed fields; validate the complete resulting period."""
    if not isinstance(data, dict):
        raise ValueError("JSON body must be an object")
    if current is None and not all(
        key in data
        for key in (
            "name",
            "start_date",
            "end_date",
            "cashback_percent",
            "card_id",
        )
    ):
        raise ValueError("Missing required fields")
    result = {
        key: data[key]
        for key in (
            "name",
            "start_date",
            "end_date",
            "cashback_percent",
            "card_id",
            "is_selected",
            "description",
            "category_type",
            "is_selection_locked",
            "max_cashback_amount",
            "min_purchase_amount",
        )
        if key in data
    }
    if "name" in result and (
        not isinstance(result["name"], str)
        or not result["name"].strip()
        or len(result["name"]) > 50
    ):
        raise ValueError("name must be a non-empty string of at most 50 characters")
    for field in ("start_date", "end_date"):
        if field in result:
            result[field] = calendar_datetime(result[field])
    start = result.get("start_date", getattr(current, "start_date", None))
    end = result.get("end_date", getattr(current, "end_date", None))
    if start >= end:
        raise ValueError("End date must be after start date")
    if "card_id" in result and (
        isinstance(result["card_id"], bool)
        or not isinstance(result["card_id"], int)
        or result["card_id"] <= 0
    ):
        raise ValueError("card_id must be a positive integer")
    for field in ("cashback_percent", "max_cashback_amount", "min_purchase_amount"):
        if field not in result:
            continue
        value = result[field]
        if value is None and field != "cashback_percent":
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{field} must be a non-negative number")
        if not math.isfinite(value) or value < 0:
            raise ValueError(f"{field} must be a finite non-negative number")
    for field in ("is_selected", "is_selection_locked"):
        if field in result and not isinstance(result[field], bool):
            raise ValueError(f"{field} must be a boolean")
    if "category_type" in result and (
        not isinstance(result["category_type"], str)
        or result["category_type"] not in CATEGORY_TYPES
    ):
        raise ValueError("Invalid category_type")
    if (
        "description" in result
        and result["description"] is not None
        and not isinstance(result["description"], str)
    ):
        raise ValueError("description must be a string or null")
    return result
