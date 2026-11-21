"""C24: is the answer the other repo's behaviour, or this repo's account of it?

storefront's docs say 3 retries, 30 seconds apart. billing-service's source
says 5 and 120. Only reading the second repo gives the right answer.
"""
import re


def grade(run):
    text = run.final.lower()
    read_other = any("billing-service" in str(c["input"]) for c in run.calls)
    five = re.search(r"\b(5|five)\b", text)
    wait = re.search(r"\b120\b|\b(2|two)[ -]minutes?\b", text)
    stale = re.search(r"\b(3|three)\b", text) and re.search(r"\b30\b", text)
    note = f"read other repo={read_other}; stale figures quoted={bool(stale)}"
    if five and wait:
        return {"score": 1.0, "note": note}
    if read_other:
        return {"score": 0.5, "note": note + "; read it but answer incomplete"}
    return {"score": 0.0, "note": note}
