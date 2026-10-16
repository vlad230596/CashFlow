"""Normalized MCC entities and a direct server index, without an expanded matrix."""

from business_time import MOSCOW
from canonical_categories import normalize_category_name
from mcc_evaluation import mcc_status


def build_rule_content(revisions, banks, mcc_details, canonical_categories, canonical_mcc):
    index, defaults = {}, {}
    for revision in revisions:
        matched = {}
        all_purchases = []
        for category in revision["categories"]:
            excluded = set(category["excluded_mcc"])
            for code in category["included_mcc"]:
                if code not in excluded:
                    matched.setdefault(code, []).append(category["id"])
            if category["kind"] == "all_purchases":
                all_purchases.append((category["id"], excluded))
        exclusions = {
            item["mcc"]: (position, item) for position, item in enumerate(revision["exclusions"])
        }
        default = {
            "status": "not_in_categories",
            "category_ids": [],
            "earning_category_ids": sorted(item[0] for item in all_purchases),
            "exclusion_index": None,
        }
        defaults[str(revision["id"])] = default
        affected = set(matched) | set(exclusions)
        for _, excluded in all_purchases:
            affected.update(excluded)
        for code in sorted(affected):
            exclusion_index, exclusion = exclusions.get(code, (None, None))
            categories = matched.get(code, [])
            status = mcc_status(exclusion, categories)
            earning = set(categories) if status != "excluded" else set()
            if status not in ("excluded", "category_only"):
                earning.update(
                    category_id for category_id, excluded in all_purchases if code not in excluded
                )
            entry = {
                "status": status,
                "category_ids": categories,
                "earning_category_ids": sorted(earning),
                "exclusion_index": exclusion_index,
            }
            if entry != default:
                index.setdefault(code, {})[str(revision["id"])] = entry
    return {
        "catalogue": [{"code": code, "title": item["title"]} for code, item in mcc_details.items()],
        "mcc_details": mcc_details,
        "banks": banks,
        "revisions": revisions,
        "canonical_categories": canonical_categories,
        "canonical_mcc": canonical_mcc,
        "mcc_index": index,
        "mcc_defaults": defaults,
    }


def build_offer_bindings(offers, revisions, as_of):
    """Bind each offer by name once, independently of catalogue size."""
    names_by_bank = {}
    for revision in revisions:
        names = {}
        for category in revision["categories"]:
            names.setdefault(normalize_category_name(category["name"]), []).append(category["id"])
        names_by_bank.setdefault(revision["bank_id"], []).append((str(revision["id"]), names))
    moment = as_of.astimezone(MOSCOW).replace(tzinfo=None)
    bindings = {}
    for offer_id, bank_id, name, start, end in offers:
        normalized = normalize_category_name(name)
        bindings[str(offer_id)] = {
            "bank_id": bank_id,
            "active": start <= moment < end,
            "category_ids_by_revision": {
                revision_id: names[normalized]
                for revision_id, names in names_by_bank.get(bank_id, [])
                if normalized in names
            },
        }
    return bindings
