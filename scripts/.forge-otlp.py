#!/usr/bin/env python3
"""Flatten forge-metrics JSON into an OTLP metrics payload.

Split out of forge-metrics.sh so the shell stays readable and this stays
testable on its own. Reads the metrics JSON on stdin.
"""
import json, os, sys

d = json.load(sys.stdin)
ts = os.environ.get("OTEL_TS", "0")
svc = os.environ.get("OTEL_SVC", "forge")
key = os.environ.get("OTEL_KEY", "unknown")

points = []
for group, vals in d.items():
    if not isinstance(vals, dict):
        continue
    for k, v in vals.items():
        # Booleans are ints in Python; they are flags, not measurements.
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            continue
        points.append({
            "name": f"forge.{group}.{k}",
            "unit": "1",
            "gauge": {"dataPoints": [{
                "asInt": int(v),
                "timeUnixNano": ts,
                "attributes": [{"key": "project", "value": {"stringValue": key}}],
            }]},
        })

json.dump({"resourceMetrics": [{
    "resource": {"attributes": [
        {"key": "service.name", "value": {"stringValue": svc}}]},
    "scopeMetrics": [{"scope": {"name": "forge-metrics"}, "metrics": points}]}]}, sys.stdout)
