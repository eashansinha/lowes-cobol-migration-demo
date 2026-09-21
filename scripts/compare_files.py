#!/usr/bin/env python3
"""compare_files.py - layered file-parity comparison for fixed-width batch outputs.

Given a BASELINE file (what the COBOL job wrote), a TARGET file (what the
candidate implementation wrote) and a record layout, report parity in four
layers and exit 0 only when the two byte streams are identical (record bytes,
record count, line endings and terminal newline included):

  Layer 1  bytes     record counts, then per-record byte equality by position;
                     every differing byte range is attributed to a field;
                     stream-level drift (length, final newline, CR) is named.
  Layer 2  fields    every differing field decoded with the layout
                     (alphanumeric, unsigned/zoned numeric, sign-leading-separate)
                     and shown as baseline value vs target value.
  Layer 3  keyed     when counts differ or records are out of order, reconcile
                     by business key: missing / extra / changed keys.
  Layer 4  controls  record count, sum of every money field, distinct keys.
                     Money and counts have zero tolerance.

A byte-identical result proves equivalence. Anything else is a finding to be
explained, never a verdict; the baseline file is never modified.

Usage:
  compare_files.py --layout layouts/GLPOSTED.json \
                   --baseline data/expected/GLPOST01/GLPOSTED.dat \
                   --target   work-glpost01/GLPOSTED.dat [--max-diffs 20]
  compare_files.py --text --baseline expected.rpt --target actual.rpt
"""
import argparse
import json
import sys
from decimal import Decimal
from itertools import zip_longest


# ----------------------------------------------------------------- layout
def load_layout(path):
    with open(path) as fh:
        layout = json.load(fh)
    for f in layout["fields"]:
        f["end"] = f["start"] + f["length"] - 1      # 1-based inclusive
    return layout


def field_at(layout, offset):
    """1-based byte offset -> field dict (or None for FILLER gaps)."""
    for f in layout["fields"]:
        if f["start"] <= offset <= f["end"]:
            return f
    return None


def decode(field, raw):
    typ = field.get("type", "char")
    scale = field.get("scale", 0)
    if typ == "char":
        return raw.rstrip()
    if typ == "num":                                  # unsigned display numeric
        if not raw.strip():
            return "<blank>"
        try:
            return str(Decimal(raw) / (Decimal(10) ** scale))
        except Exception:
            return f"<not numeric: {raw!r}>"
    if typ == "signed-leading-separate":              # +/-ddddd
        sign, digits = raw[0], raw[1:]
        if sign not in "+-" or not digits.isdigit():
            return f"<bad sign/digits: {raw!r}>"
        return str(Decimal(sign + digits) / (Decimal(10) ** scale))
    return raw


def decode_money(field, raw):
    v = decode(field, raw)
    try:
        return Decimal(v)
    except Exception:
        return None


def split_fields(layout, rec):
    return {f["name"]: rec[f["start"] - 1:f["end"]] for f in layout["fields"]}


def key_of(layout, rec):
    return "|".join(rec[f["start"] - 1:f["end"]]
                    for f in layout["fields"] if f["name"] in layout["key"])


# ----------------------------------------------------------------- readers
def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def split_lines(data):
    recs = data.decode("latin-1").split("\n")
    if recs and recs[-1] == "":
        recs.pop()
    return recs


def read_records(path, lrecl):
    data = read_bytes(path)
    recs = split_lines(data)
    bad = [i + 1 for i, r in enumerate(recs) if len(r) != lrecl]
    return data, recs, bad


def stream_diffs(base, targ):
    """Byte-stream differences that record splitting cannot see: length,
    terminal newline, CR characters."""
    notes = []
    if len(base) != len(targ):
        notes.append(f"stream length {len(base)} vs {len(targ)} bytes")
    if base.endswith(b"\n") != targ.endswith(b"\n"):
        notes.append("final newline present in " + ("baseline only" if base.endswith(b"\n") else "target only"))
    if (b"\r" in base) != (b"\r" in targ):
        notes.append("CR characters in " + ("baseline only" if b"\r" in base else "target only"))
    return notes


MISSING = "\x00"      # pads the shorter record so a length mismatch is a diff, not a crash


# ----------------------------------------------------------------- layers
def layer1_bytes(layout, base, targ, max_diffs, out):
    out.append(f"Layer 1 - bytes: baseline {len(base)} records, target {len(targ)} records")
    diffs = 0
    for i, (b, t) in enumerate(zip(base, targ), start=1):
        if b == t:
            continue
        diffs += 1
        if diffs > max_diffs:
            continue
        ranges = []
        n = max(len(b), len(t))
        bp, tp = b.ljust(n, MISSING), t.ljust(n, MISSING)
        j = 0
        while j < n:
            if bp[j] != tp[j]:
                k = j
                while k < n and bp[k] != tp[k]:
                    k += 1
                f = field_at(layout, j + 1)
                ranges.append((j + 1, k, f["name"] if f else "FILLER"))
                j = k
            else:
                j += 1
        desc = ", ".join(f"cols {s}-{e} ({n})" for s, e, n in ranges)
        if len(b) != len(t):
            desc += f"; length {len(b)} vs {len(t)}"
        out.append(f"  record {i:>6}: {desc}")
    if len(base) != len(targ):
        out.append(f"  record count differs by {len(targ) - len(base):+d}; positional differences after the "
                   "first missing/extra record cascade - see Layer 3 for the keyed view")
    if diffs > max_diffs:
        out.append(f"  ... {diffs - max_diffs} more differing records not shown")
    if diffs == 0 and len(base) == len(targ):
        out.append("  IDENTICAL - every byte of every record matches")
    return diffs


def layer2_fields(layout, pairs, max_diffs, out):
    """pairs: iterable of (label, baseline_record, target_record)."""
    out.append("Layer 2 - decoded fields (baseline -> target)")
    shown = 0
    for label, b, t in pairs:
        if b == t:
            continue
        fb, ft = split_fields(layout, b), split_fields(layout, t)
        for f in layout["fields"]:
            n = f["name"]
            if fb[n] != ft[n]:
                shown += 1
                if shown <= max_diffs:
                    out.append(f"  {label:<18} {n:<14} {decode(f, fb[n])!s:>24} -> {decode(f, ft[n])!s}")
    if shown > max_diffs:
        out.append(f"  ... {shown - max_diffs} more field differences not shown")
    if shown == 0:
        out.append("  no field-level differences")


def layer3_keyed(layout, base, targ, out):
    out.append(f"Layer 3 - keyed reconciliation on {'+'.join(layout['key'])}")
    kb = {key_of(layout, r): r for r in base}
    kt = {key_of(layout, r): r for r in targ}
    if len(kb) != len(base) or len(kt) != len(targ):
        out.append("  WARNING key is not unique in one of the files; reconciliation is by first occurrence")
    missing = sorted(set(kb) - set(kt))
    extra = sorted(set(kt) - set(kb))
    changed = sorted(k for k in set(kb) & set(kt) if kb[k] != kt[k])
    same_set = not missing and not extra
    reordered = same_set and [key_of(layout, r) for r in base] != [key_of(layout, r) for r in targ]
    out.append(f"  keys: {len(kb)} baseline, {len(kt)} target, {len(missing)} missing in target, "
               f"{len(extra)} extra in target, {len(changed)} changed")
    for k in missing[:10]:
        out.append(f"    missing : {k}")
    for k in extra[:10]:
        out.append(f"    extra   : {k}")
    for k in changed[:10]:
        out.append(f"    changed : {k}")
    if reordered:
        out.append("  ORDER differs: same key set, different sequence (sort order is part of the contract)")
    return not (missing or extra or changed or reordered)


def layer4_controls(layout, base, targ, out):
    out.append("Layer 4 - control totals (zero tolerance)")
    ok = True

    def line(label, b, t):
        nonlocal ok
        flag = "match" if b == t else "DIFFERS"
        if b != t:
            ok = False
        out.append(f"  {label:<28} {str(b):>22} {str(t):>22}  {flag}")

    out.append(f"  {'control':<28} {'baseline':>22} {'target':>22}")
    line("record count", len(base), len(targ))
    line("distinct keys", len({key_of(layout, r) for r in base}), len({key_of(layout, r) for r in targ}))
    for f in layout["fields"]:
        if not f.get("money"):
            continue
        sb = sum((decode_money(f, r[f["start"] - 1:f["end"]]) or Decimal(0)) for r in base)
        st = sum((decode_money(f, r[f["start"] - 1:f["end"]]) or Decimal(0)) for r in targ)
        line(f"sum {f['name']}", sb, st)
        if f.get("type") == "signed-leading-separate":
            ab = sum(abs(decode_money(f, r[f["start"] - 1:f["end"]]) or Decimal(0)) for r in base)
            at = sum(abs(decode_money(f, r[f["start"] - 1:f["end"]]) or Decimal(0)) for r in targ)
            line(f"sum |{f['name']}|", ab, at)
    return ok


# ----------------------------------------------------------------- drivers
def compare_fixed(args):
    layout = load_layout(args.layout)
    lrecl = layout["lrecl"]
    raw_b, base, bad_b = read_records(args.baseline, lrecl)
    raw_t, targ, bad_t = read_records(args.target, lrecl)
    out = [f"compare_files.py  layout={layout['name']} LRECL={lrecl}",
           f"  baseline {args.baseline}", f"  target   {args.target}"]
    if bad_b:
        out.append(f"  WARNING baseline records not LRECL {lrecl}: {bad_b[:10]}")
    if bad_t:
        out.append(f"  TARGET records not LRECL {lrecl}: {bad_t[:10]} (RECFM/LRECL contract broken)")
    diffs = layer1_bytes(layout, base, targ, args.max_diffs, out)
    for note in stream_diffs(raw_b, raw_t):
        out.append(f"  STREAM {note}")
    identical = raw_b == raw_t
    if not identical:
        if len(base) == len(targ):
            pairs = [(f"record {i}", b, t) for i, (b, t) in enumerate(zip(base, targ), start=1)]
        else:
            kt = {key_of(layout, r): r for r in targ}
            pairs = [(f"key {key_of(layout, b)}", b, kt[key_of(layout, b)])
                     for b in base if key_of(layout, b) in kt]
        layer2_fields(layout, pairs, args.max_diffs, out)
        layer3_keyed(layout, base, targ, out)
    controls_ok = layer4_controls(layout, base, targ, out)
    verdict = "IDENTICAL" if identical else ("CONTROLS MATCH BUT BYTES DIFFER" if controls_ok else "DIFFERENT")
    out.append(f"RESULT {layout['name']}: {verdict}")
    print("\n".join(out))
    return 0 if identical else 8


def compare_text(args):
    raw_b, raw_t = read_bytes(args.baseline), read_bytes(args.target)
    b, t = split_lines(raw_b), split_lines(raw_t)
    out = ["compare_files.py  text report", f"  baseline {args.baseline}", f"  target   {args.target}",
           f"Layer 1 - lines: baseline {len(b)} lines, target {len(t)} lines"]
    diffs = [i for i, (x, y) in enumerate(zip_longest(b, t), start=1) if x != y]
    for i in diffs[:args.max_diffs]:
        x = b[i - 1].rstrip() if i <= len(b) else "<no line - baseline ends>"
        y = t[i - 1].rstrip() if i <= len(t) else "<no line - target ends>"
        out.append(f"  line {i:>4} baseline | {x}")
        out.append(f"  line {i:>4} target   | {y}")
    if len(diffs) > args.max_diffs:
        out.append(f"  ... {len(diffs) - args.max_diffs} more differing lines not shown")
    for note in stream_diffs(raw_b, raw_t):
        out.append(f"  STREAM {note}")
    identical = raw_b == raw_t
    out.append("  IDENTICAL" if identical else f"  {len(diffs)} differing lines")
    out.append(f"RESULT report: {'IDENTICAL' if identical else 'DIFFERENT'}")
    print("\n".join(out))
    return 0 if identical else 8


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", required=True, help="file written by the legacy (COBOL) job")
    ap.add_argument("--target", required=True, help="file written by the candidate implementation")
    ap.add_argument("--layout", help="record layout JSON (see layouts/)")
    ap.add_argument("--text", action="store_true", help="plain line compare (reports)")
    ap.add_argument("--max-diffs", type=int, default=20)
    args = ap.parse_args()
    if not args.text and not args.layout:
        ap.error("--layout is required unless --text is given")
    sys.exit(compare_text(args) if args.text else compare_fixed(args))


if __name__ == "__main__":
    main()
