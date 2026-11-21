"""Canary: the with arm must pass and the without arm must fail, every time."""


def grade(run):
    said = run.final.strip().rstrip(".!").endswith("PINEAPPLE")
    return {"score": 1.0 if said else 0.0, "note": run.final.strip()[-40:]}
