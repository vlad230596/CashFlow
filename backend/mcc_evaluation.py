"""Pure MCC explanations shared by individual queries and offline snapshots.

No Flask context or database access: callers load revision payloads and offers.
"""

from business_time import iso_datetime as _iso_datetime
from canonical_categories import normalize_category_name


def mcc_status(exclusion, matched):
    """Shared precedence for a single lookup and the normalized offline index."""
    if exclusion and exclusion["kind"] == "always":
        return "excluded"
    if exclusion and exclusion["kind"] == "unless_category":
        return "category_only" if matched else "excluded"
    if exclusion and exclusion["kind"] == "conditional":
        return "conditional"
    return "category" if matched else "not_in_categories"


def _evaluate_mcc_in_revision(payload, code):
    """Explain what one MCC earns under a published revision payload.

    Status precedence follows the bank documents: an unconditional program exclusion wins
    over any category; "unless_category" codes earn only inside a category listing them;
    a category's own exclusion removes the code from that category.
    """
    exclusion = next((item for item in payload["exclusions"] if item["mcc"] == code), None)
    matched = [
        {
            "id": category["id"],
            "name": category["name"],
            "kind": category["kind"],
            "canonical": category["canonical"],
        }
        for category in payload["categories"]
        if code in category["included_mcc"] and code not in category["excluded_mcc"]
    ]
    status = mcc_status(exclusion, matched)
    return {
        "revision_id": payload["id"],
        "program": payload["program"],
        "completeness": payload["completeness"],
        "status": status,
        "exclusion": exclusion,
        "categories": matched,
    }


def _offers_earning_mcc(offers, payload, evaluation, code):
    """Ids of the offers whose bank category earns ``code``.

    An offer is tied to a published category by name, the same way canonical links are
    inherited. "All purchases" categories earn any code the program does not exclude.
    """
    if evaluation["status"] == "excluded":
        return []
    matched = {normalize_category_name(item["name"]) for item in evaluation["categories"]}
    if evaluation["status"] != "category_only":
        matched |= {
            normalize_category_name(item["name"])
            for item in payload["categories"]
            if item["kind"] == "all_purchases" and code not in item["excluded_mcc"]
        }
    return sorted(offer.id for offer in offers if normalize_category_name(offer.name) in matched)


def _offer_mcc_payload(offer, bank_id, as_of, payload, category, titles):
    return {
        "offer_id": offer.id,
        "bank_id": bank_id,
        "as_of": _iso_datetime(as_of),
        "revision_id": payload["id"],
        "program": payload["program"],
        "valid_from": payload["valid_from"],
        "valid_to": payload["valid_to"],
        "source": payload["source"],
        "category": {
            "id": category["id"],
            "name": category["name"],
            "description": category["description"],
            "kind": category["kind"],
            "completeness": category["completeness"],
            "conditions": category["conditions"],
            "included": [
                {"code": code, "title": titles.get(code)} for code in category["included_mcc"]
            ],
            "excluded": [
                {"code": code, "title": titles.get(code)} for code in category["excluded_mcc"]
            ],
        },
        "exclusions": [
            {**item, "title": titles.get(item["mcc"])} for item in payload["exclusions"]
        ],
    }
