"""Compact offline snapshot transport without repeated per-code/per-offer rules."""

import json


def compact_snapshot(expanded):
    """Intern identical verdicts and offer rules while preserving exact API values."""

    def intern(value, identities, payloads):
        key = json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        if key not in identities:
            identity = str(len(identities))
            identities[key] = identity
            payloads[identity] = value
        return identities[key]

    lookup_payloads, lookup_refs, lookup_identities = {}, {}, {}
    mcc_details, canonical = {}, {}
    for code, lookup in expanded["lookups"].items():
        mcc_details[code] = lookup["mcc"]
        if lookup["canonical"]:
            canonical[code] = lookup["canonical"]
        lookup_refs[code] = [
            intern(bank, lookup_identities, lookup_payloads) for bank in lookup["banks"]
        ]
    offer_payloads, offer_refs, offer_identities = {}, {}, {}
    for offer_id, rules in expanded["offer_rules"].items():
        if rules is None:
            offer_refs[offer_id] = None
            continue
        shared = {key: value for key, value in rules.items() if key not in ("offer_id", "as_of")}
        offer_refs[offer_id] = intern(shared, offer_identities, offer_payloads)
    result = {
        "schema_version": 2,
        "as_of": expanded["as_of"],
        "generated_at": expanded["generated_at"],
        "catalogue": expanded["catalogue"],
        "mcc_details": mcc_details,
        "canonical": canonical,
        "lookup_refs": lookup_refs,
        "lookup_payloads": lookup_payloads,
        "offer_rule_refs": offer_refs,
        "offer_rule_payloads": offer_payloads,
    }
    # Metadata, exclusions and titled MCC arrays recur in many distinct
    # verdicts/categories. Deduplicate nested structures too, otherwise even
    # one complete day can exceed a browser's localStorage quota.
    sections = ("lookup_payloads", "offer_rule_payloads", "canonical")
    counts = {}

    def fingerprint(value):
        return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))

    def count(value):
        if isinstance(value, (dict, list)):
            key = fingerprint(value)
            if len(key) >= 48:
                counts[key] = counts.get(key, 0) + 1
            for child in value.values() if isinstance(value, dict) else value:
                count(child)

    for section in sections:
        for value in result[section].values():
            count(value)
    shared, shared_ids = {}, {}

    def encode(value):
        if not isinstance(value, (dict, list)):
            return value
        key = fingerprint(value)
        if counts.get(key, 0) > 1 and key in shared_ids:
            return {"$ref": shared_ids[key]}
        encoded = (
            {name: encode(child) for name, child in value.items()}
            if isinstance(value, dict)
            else [encode(child) for child in value]
        )
        if counts.get(key, 0) > 1:
            identity = str(len(shared_ids))
            shared_ids[key] = identity
            shared[identity] = encoded
            return {"$ref": identity}
        return encoded

    for section in sections:
        result[section] = {key: encode(value) for key, value in result[section].items()}
    result["shared_payloads"] = shared
    return result
