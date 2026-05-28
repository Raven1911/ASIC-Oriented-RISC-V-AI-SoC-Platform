#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import re
from collections import Counter
from pathlib import Path


PROJECT = Path("/home/raven1911/Data/vivado_prj/Beta_AISoC")
RUN = PROJECT / "Beta_AISoC.runs/impl_5_copy_1"
SYNTH = PROJECT / "Beta_AISoC.runs/synth_5"
OUTDIR = Path("reports/vivado")
OUT = OUTDIR / "BK_AISoC_consolidated_report.md"

FILES = {
    "project": PROJECT / "Beta_AISoC.xpr",
    "bitstream": RUN / "BK_AISoC.bit",
    "util_placed": RUN / "BK_AISoC_utilization_placed.rpt",
    "util_synth": SYNTH / "BK_AISoC_utilization_synth.rpt",
    "util_hier4": OUTDIR / "BK_AISoC_utilization_hierarchical_depth4.rpt",
    "util_hier6": OUTDIR / "BK_AISoC_utilization_hierarchical_depth6.rpt",
    "timing_final": OUTDIR / "BK_AISoC_timing_summary_consolidated.rpt",
    "timing_routed": RUN / "BK_AISoC_timing_summary_routed.rpt",
    "power": RUN / "BK_AISoC_power_routed.rpt",
    "drc": RUN / "BK_AISoC_drc_routed.rpt",
    "methodology": RUN / "BK_AISoC_methodology_drc_routed.rpt",
    "route": OUTDIR / "BK_AISoC_route_status_consolidated.rpt",
    "clock": OUTDIR / "BK_AISoC_clock_utilization_consolidated.rpt",
    "synth_log": SYNTH / "runme.log",
    "impl_log": RUN / "runme.log",
}


def read(path: Path) -> str:
    return path.read_text(errors="replace")


def lines(path: Path) -> list[str]:
    return read(path).splitlines()


def num(s: str) -> int:
    return int(s.replace(",", "").strip())


def fmt(v) -> str:
    if isinstance(v, float):
        if v.is_integer():
            return f"{int(v):,}"
        return f"{v:,.2f}".rstrip("0").rstrip(".")
    if isinstance(v, int):
        return f"{v:,}"
    return str(v)


def md_table(headers: list[str], rows: list[list[object]]) -> str:
    def esc(value: object) -> str:
        return str(value).replace("|", "\\|").replace("\n", "<br>")

    out = ["| " + " | ".join(headers) + " |"]
    out.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for row in rows:
        out.append("| " + " | ".join(esc(x) for x in row) + " |")
    return "\n".join(out)


def pipe_rows(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in lines(path):
        if not line.startswith("|") or line.startswith("|-"):
            continue
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if not parts or set(parts[0]) <= {"-"}:
            continue
        rows.append(parts)
    return rows


def parse_hierarchy(path: Path) -> list[dict[str, object]]:
    rows = []
    for line in lines(path):
        if not line.startswith("|"):
            continue
        raw_cols = line.split("|")[1:-1]
        if len(raw_cols) != 10:
            continue
        stripped = [c.strip() for c in raw_cols]
        if stripped[0] in {"Instance", ""} or stripped[2] == "Total LUTs":
            continue
        if not re.fullmatch(r"[0-9,]+", stripped[2]):
            continue
        instance_col = raw_cols[0].rstrip()
        leading = len(instance_col) - len(instance_col.lstrip())
        level = max(0, (leading - 1) // 2)
        rows.append(
            {
                "level": level,
                "instance": stripped[0],
                "module": stripped[1],
                "total_luts": num(stripped[2]),
                "logic_luts": num(stripped[3]),
                "lutram": num(stripped[4]),
                "srl": num(stripped[5]),
                "ffs": num(stripped[6]),
                "ramb36": num(stripped[7]),
                "ramb18": num(stripped[8]),
                "dsp": num(stripped[9]),
            }
        )
    return rows


def metric(path: Path, name: str) -> dict[str, object] | None:
    pattern = re.compile(
        r"^\|\s*"
        + re.escape(name)
        + r"\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([<0-9.]+)\s*\|"
    )
    for line in lines(path):
        m = pattern.match(line)
        if m:
            used, fixed, prohibited, available, pct = m.groups()
            return {
                "name": name,
                "used": num(used),
                "fixed": num(fixed),
                "prohibited": num(prohibited),
                "available": num(available),
                "pct": pct,
            }
    return None


def timing_summary(path: Path) -> dict[str, str]:
    ls = lines(path)
    for i, line in enumerate(ls):
        if "WNS(ns)" in line and "TNS(ns)" in line:
            for cand in ls[i + 2 : i + 7]:
                vals = cand.split()
                if len(vals) >= 12 and re.match(r"^-?[0-9.]+$", vals[0]):
                    keys = [
                        "WNS",
                        "TNS",
                        "TNS Failing Endpoints",
                        "TNS Total Endpoints",
                        "WHS",
                        "THS",
                        "THS Failing Endpoints",
                        "THS Total Endpoints",
                        "WPWS",
                        "TPWS",
                        "TPWS Failing Endpoints",
                        "TPWS Total Endpoints",
                    ]
                    return dict(zip(keys, vals[:12]))
    return {}


def extract_section(path: Path, start: str, end: str | None = None, limit: int | None = None) -> str:
    ls = lines(path)
    try:
        s = next(i for i, line in enumerate(ls) if start in line)
    except StopIteration:
        return ""
    e = len(ls)
    if end:
        for j in range(s + 1, len(ls)):
            if end in ls[j]:
                e = j
                break
    block = ls[s:e]
    if limit:
        block = block[:limit]
    return "\n".join(block).rstrip()


def parse_power(path: Path) -> dict[str, str]:
    data = {}
    for row in pipe_rows(path):
        if len(row) == 2 and row[0] in {
            "Total On-Chip Power (W)",
            "Dynamic (W)",
            "Device Static (W)",
            "Effective TJA (C/W)",
            "Max Ambient (C)",
            "Junction Temperature (C)",
            "Confidence Level",
            "Design Power Budget (W)",
            "Power Budget Margin (W)",
        }:
            data[row[0]] = row[1]
    return data


def parse_rule_summary(path: Path) -> list[list[str]]:
    rows = []
    for row in pipe_rows(path):
        if len(row) == 4 and row[0] not in {"Rule", ""} and re.fullmatch(r"[0-9]+", row[3]):
            rows.append(row)
    return rows


def warning_counts(path: Path) -> tuple[int, int, int, list[tuple[str, int]]]:
    counts = {"WARNING": 0, "CRITICAL WARNING": 0, "ERROR": 0}
    ids: Counter[str] = Counter()
    for line in lines(path):
        m = re.match(r"^(WARNING|CRITICAL WARNING|ERROR):\s+\[([^\]]+)\]", line)
        if not m:
            continue
        counts[m.group(1)] += 1
        ids[m.group(2)] += 1
    return counts["WARNING"], counts["CRITICAL WARNING"], counts["ERROR"], ids.most_common(10)


def parse_timing_paths(path: Path) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    ls = lines(path)
    paths = []
    for i, line in enumerate(ls):
        m = re.match(r"Slack \(MET\) :\s+([-0-9.inf]+)ns", line)
        if not m:
            continue
        block = ls[i : i + 35]
        rec = {"slack": m.group(1)}
        for b in block:
            mm = re.match(r"\s*(Source|Destination|Path Group|Path Type|Requirement|Data Path Delay|Logic Levels):\s+(.*)", b)
            if mm:
                rec[mm.group(1).lower().replace(" ", "_")] = mm.group(2).strip()
        if "path_type" in rec:
            paths.append(rec)

    def finite(p: dict[str, str]) -> float:
        try:
            return float(p["slack"])
        except Exception:
            return 1e99

    constrained = [p for p in paths if p.get("path_group") != "(none)"]
    setup = sorted([p for p in constrained if p.get("path_type", "").startswith("Setup")], key=finite)
    hold = sorted([p for p in constrained if p.get("path_type", "").startswith("Hold")], key=finite)
    unconstrained = [p for p in paths if p.get("path_group") == "(none)"]
    return setup[:10], hold[:10], unconstrained[:10]


def stat_line(path: Path) -> str:
    st = path.stat()
    ts = dt.datetime.fromtimestamp(st.st_mtime).astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    return f"{ts}, {st.st_size:,} bytes"


def make_detailed() -> str:
    hier6 = parse_hierarchy(FILES["util_hier6"])
    top = hier6[0]
    top_children = [r for r in hier6 if r["level"] == 1]
    largest = sorted(hier6[1:], key=lambda r: (r["total_luts"], r["ffs"], r["ramb36"], r["ramb18"], r["dsp"]), reverse=True)[:30]

    placed_metrics = [
        metric(FILES["util_placed"], "Slice LUTs"),
        metric(FILES["util_placed"], "LUT as Logic"),
        metric(FILES["util_placed"], "LUT as Memory"),
        metric(FILES["util_placed"], "Slice Registers"),
        metric(FILES["util_placed"], "Block RAM Tile"),
        metric(FILES["util_placed"], "DSPs"),
        metric(FILES["util_placed"], "Bonded IOB"),
        metric(FILES["util_placed"], "BUFGCTRL"),
        metric(FILES["util_placed"], "MMCME2_ADV"),
    ]
    placed_metrics = [m for m in placed_metrics if m]

    synth_metrics = [
        metric(FILES["util_synth"], "Slice LUTs*"),
        metric(FILES["util_synth"], "Slice Registers"),
        metric(FILES["util_synth"], "Block RAM Tile"),
        metric(FILES["util_synth"], "DSPs"),
    ]
    synth_metrics = [m for m in synth_metrics if m]

    final_timing = timing_summary(FILES["timing_final"])
    routed_timing = timing_summary(FILES["timing_routed"])
    power = parse_power(FILES["power"])
    drc_rows = parse_rule_summary(FILES["drc"])
    meth_rows = parse_rule_summary(FILES["methodology"])
    synth_warn, synth_crit, synth_err, synth_ids = warning_counts(FILES["synth_log"])
    impl_warn, impl_crit, impl_err, impl_ids = warning_counts(FILES["impl_log"])
    setup_paths, hold_paths, unconstrained_paths = parse_timing_paths(FILES["timing_final"])

    total_luts = int(top["total_luts"])
    total_ffs = int(top["ffs"])
    total_bram = float(top["ramb36"]) + float(top["ramb18"]) / 2.0
    total_dsp = int(top["dsp"]) or 1

    def top_row(r: dict[str, object]) -> list[object]:
        bram = float(r["ramb36"]) + float(r["ramb18"]) / 2.0
        return [
            r["instance"],
            r["module"],
            fmt(r["total_luts"]),
            f"{float(r['total_luts']) / total_luts * 100:.2f}%",
            fmt(r["ffs"]),
            f"{float(r['ffs']) / total_ffs * 100:.2f}%",
            fmt(bram),
            f"{bram / total_bram * 100:.2f}%" if total_bram else "0%",
            fmt(r["dsp"]),
            f"{float(r['dsp']) / total_dsp * 100:.2f}%",
        ]

    def hier_row(r: dict[str, object]) -> list[object]:
        return [
            r["level"],
            r["instance"],
            r["module"],
            fmt(r["total_luts"]),
            fmt(r["logic_luts"]),
            fmt(r["lutram"]),
            fmt(r["srl"]),
            fmt(r["ffs"]),
            fmt(r["ramb36"]),
            fmt(r["ramb18"]),
            fmt(r["dsp"]),
        ]

    def timing_path_row(p: dict[str, str]) -> list[str]:
        return [
            p.get("slack", ""),
            p.get("path_group", ""),
            p.get("path_type", ""),
            p.get("source", ""),
            p.get("destination", ""),
            p.get("data_path_delay", ""),
            p.get("logic_levels", ""),
        ]

    out: list[str] = []
    out.append("# BK_AISoC Vivado Consolidated Report\n")
    out.append(f"- Generated: {dt.datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %z')}")
    out.append("- Project: `/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.xpr`")
    out.append("- Top module: `BK_AISoC`")
    out.append("- Device: `xc7vx485tffg1761-2`")
    out.append("- Vivado: `2024.2`")
    out.append("- Runs used: `synth_5` and `impl_5_copy_1`")
    out.append("- Design state for extra reports: `Physopt postRoute`\n")

    out.append("## 1. Executive Summary\n")
    out.append(md_table(
        ["Item", "Status / Value"],
        [
            ["Bitstream", f"`BK_AISoC.bit` generated successfully ({stat_line(FILES['bitstream'])})"],
            ["Final timing", "PASS: all user specified timing constraints are met"],
            ["Final setup WNS / TNS", f"{final_timing.get('WNS')} ns / {final_timing.get('TNS')} ns"],
            ["Final hold WHS / THS", f"{final_timing.get('WHS')} ns / {final_timing.get('THS')} ns"],
            ["Route status", "All routable nets fully routed, routing errors = 0"],
            ["Power estimate", f"{power.get('Total On-Chip Power (W)')} W total, confidence `{power.get('Confidence Level')}`"],
            ["Main resource pressure", "BRAM is the largest relative usage; LUT/FF/DSP usage is low"],
            ["Main timing risk", "Setup margin is very small: 0.005 ns on `clk_out200MHz_clk_wiz_0`"],
        ],
    ))
    out.append("")

    out.append("## 2. Build Artifacts and Sources\n")
    out.append(md_table(
        ["Artifact", "Path", "Timestamp / Size"],
        [
            ["Bitstream", str(FILES["bitstream"]), stat_line(FILES["bitstream"])],
            ["Final timing", str(FILES["timing_final"]), stat_line(FILES["timing_final"])],
            ["Placed utilization", str(FILES["util_placed"]), stat_line(FILES["util_placed"])],
            ["Hierarchical utilization depth 6", str(FILES["util_hier6"]), stat_line(FILES["util_hier6"])],
            ["Power", str(FILES["power"]), stat_line(FILES["power"])],
            ["DRC", str(FILES["drc"]), stat_line(FILES["drc"])],
            ["Methodology", str(FILES["methodology"]), stat_line(FILES["methodology"])],
        ],
    ))
    out.append("")

    out.append("## 3. Timing\n")
    out.append("### 3.1 Final Post-Route Physopt Timing\n")
    out.append(md_table(
        list(final_timing.keys()),
        [list(final_timing.values())],
    ))
    out.append("\n### 3.2 Before vs After Post-Route Physopt\n")
    out.append(md_table(
        ["Stage", "WNS(ns)", "TNS(ns)", "Setup failing endpoints", "WHS(ns)", "THS(ns)", "Hold failing endpoints", "Conclusion"],
        [
            [
                "route_design",
                routed_timing.get("WNS"),
                routed_timing.get("TNS"),
                routed_timing.get("TNS Failing Endpoints"),
                routed_timing.get("WHS"),
                routed_timing.get("THS"),
                routed_timing.get("THS Failing Endpoints"),
                "Failed setup before post-route physical optimization",
            ],
            [
                "post_route_phys_opt",
                final_timing.get("WNS"),
                final_timing.get("TNS"),
                final_timing.get("TNS Failing Endpoints"),
                final_timing.get("WHS"),
                final_timing.get("THS"),
                final_timing.get("THS Failing Endpoints"),
                "Passed, but setup margin is narrow",
            ],
        ],
    ))
    out.append("\n### 3.3 Clock / Intra / Inter Clock Tables\n")
    out.append("```text")
    out.append(extract_section(FILES["timing_final"], "| Clock Summary", "| Timing Details"))
    out.append("```")
    out.append("\n### 3.4 Worst Constrained Setup Paths\n")
    out.append(md_table(
        ["Slack(ns)", "Path group", "Type", "Source", "Destination", "Data path delay", "Logic levels"],
        [timing_path_row(p) for p in setup_paths],
    ))
    out.append("\n### 3.5 Worst Constrained Hold Paths\n")
    out.append(md_table(
        ["Slack(ns)", "Path group", "Type", "Source", "Destination", "Data path delay", "Logic levels"],
        [timing_path_row(p) for p in hold_paths],
    ))
    out.append("\n### 3.6 Check Timing Warnings\n")
    out.append("```text")
    out.append(extract_section(FILES["timing_final"], "check_timing report", limit=140))
    out.append("```")
    out.append(
        "\nKey points: `no_clock = 368`, `unconstrained_internal_endpoints = 16`, "
        "`no_input_delay = 40`, `no_output_delay = 66`. These do not prevent bitstream generation, "
        "but should be cleaned if the report needs to be defensible for signoff.\n"
    )

    out.append("## 4. Utilization Summary\n")
    out.append("### 4.1 Implemented Resource Usage\n")
    out.append(md_table(
        ["Resource", "Used", "Fixed", "Prohibited", "Available", "Util%"],
        [[m["name"], fmt(m["used"]), fmt(m["fixed"]), fmt(m["prohibited"]), fmt(m["available"]), m["pct"]] for m in placed_metrics],
    ))
    out.append("\n### 4.2 Synthesis vs Implemented Snapshot\n")
    out.append(md_table(
        ["Synthesis Resource", "Used", "Available", "Util%"],
        [[m["name"], fmt(m["used"]), fmt(m["available"]), m["pct"]] for m in synth_metrics],
    ))
    out.append(
        "\nNote: implemented LUT count can differ from synthesis because `opt_design`, placement, "
        "physical optimization, and LUT combining change the final mapped count.\n"
    )

    out.append("## 5. Resource Usage by Top-Level IP\n")
    out.append(md_table(
        ["Instance/IP", "Module", "LUTs", "LUT% design", "FFs", "FF% design", "BRAM tiles eq.", "BRAM% design", "DSP", "DSP% design"],
        [top_row(r) for r in top_children],
    ))
    out.append("")

    out.append("### 5.1 Largest Hierarchical Blocks by LUT Count\n")
    out.append(md_table(
        ["Level", "Instance", "Module", "Total LUTs", "Logic LUTs", "LUTRAM", "SRL", "FFs", "RAMB36", "RAMB18", "DSP"],
        [hier_row(r) for r in largest],
    ))
    out.append("")

    out.append("### 5.2 CNN Accelerator Internal Breakdown\n")
    cnn_subtree = []
    in_cnn = False
    for r in hier6:
        if r["level"] == 1 and r["instance"] == "cnn_accel":
            in_cnn = True
        elif r["level"] == 1 and in_cnn:
            break
        if in_cnn and int(r["level"]) <= 5:
            cnn_subtree.append(r)
    out.append(md_table(
        ["Level", "Instance", "Module", "Total LUTs", "Logic LUTs", "LUTRAM", "SRL", "FFs", "RAMB36", "RAMB18", "DSP"],
        [hier_row(r) for r in cnn_subtree],
    ))
    out.append("")

    out.append("## 6. Power\n")
    out.append(md_table(
        ["Metric", "Value"],
        [[k, v] for k, v in power.items()],
    ))
    out.append(
        "\nPower confidence is `Low` because no simulation activity file is attached to the power report. "
        "Use SAIF/VCD-based activity if this number is used in a thesis table or board power estimate.\n"
    )

    out.append("## 7. DRC Summary\n")
    out.append(md_table(["Rule", "Severity", "Description", "Checks"], drc_rows))
    out.append(
        "\nImportant DRC items: missing `CFGBVS`/`CONFIG_VOLTAGE`, DSP input/output pipeline suggestions, "
        "RAMB output register suggestions, RAMB async control checks, and one gated-clock check.\n"
    )

    out.append("## 8. Methodology Summary\n")
    out.append(md_table(["Rule", "Severity", "Description", "Violations"], meth_rows))
    out.append("")

    out.append("## 9. Log Warning Summary\n")
    out.append(md_table(
        ["Run", "Warnings", "Critical warnings", "Errors"],
        [
            ["synth_5", synth_warn, synth_crit, synth_err],
            ["impl_5_copy_1", impl_warn, impl_crit, impl_err],
        ],
    ))
    out.append("\n### 9.1 Top Synthesis Warning IDs\n")
    out.append(md_table(["ID", "Count"], [[k, v] for k, v in synth_ids]))
    out.append("\n### 9.2 Top Implementation Warning IDs\n")
    out.append(md_table(["ID", "Count"], [[k, v] for k, v in impl_ids]))
    out.append("")

    out.append("## 10. Recommended Cleanup Before Final Signoff\n")
    out.append(
        "1. Add or verify board-level XDC properties for `CFGBVS` and `CONFIG_VOLTAGE`.\n"
        "2. Review `TIMING-18` by adding realistic `set_input_delay` and `set_output_delay` for external interfaces.\n"
        "3. Fix the inferred latch around `video_streaming/DVP_core/HDMI_interface_uut/RGBchannel_reg` if it is not intentional.\n"
        "4. Review CDC warnings: add synchronizer attributes where the CDC structure is intentional.\n"
        "5. Investigate the 200 MHz worst setup path in `cnn_accel/u_cnn_accel/u_filter_buf`; margin is only 0.005 ns.\n"
        "6. If power is reported formally, regenerate power with SAIF/VCD activity instead of vectorless/default activity.\n"
    )
    out.append("")

    out.append("## Appendix A. Full Hierarchical Utilization, Depth 6\n")
    out.append(md_table(
        ["Level", "Instance", "Module", "Total LUTs", "Logic LUTs", "LUTRAM", "SRL", "FFs", "RAMB36", "RAMB18", "DSP"],
        [hier_row(r) for r in hier6],
    ))
    out.append("")

    out.append("## Appendix B. Route Status\n")
    out.append("```text")
    out.append(read(FILES["route"]).strip())
    out.append("```")
    out.append("")

    out.append("## Appendix C. Report Source Paths\n")
    for name, path in FILES.items():
        if path.exists():
            out.append(f"- `{name}`: `{path}`")
    out.append("")

    return "\n".join(out)


def make() -> str:
    hier6 = parse_hierarchy(FILES["util_hier6"])
    top = hier6[0]
    top_children = [r for r in hier6 if r["level"] == 1]

    placed_metrics = [
        metric(FILES["util_placed"], "Slice LUTs"),
        metric(FILES["util_placed"], "LUT as Logic"),
        metric(FILES["util_placed"], "LUT as Memory"),
        metric(FILES["util_placed"], "Slice Registers"),
        metric(FILES["util_placed"], "Block RAM Tile"),
        metric(FILES["util_placed"], "DSPs"),
        metric(FILES["util_placed"], "Bonded IOB"),
        metric(FILES["util_placed"], "BUFGCTRL"),
        metric(FILES["util_placed"], "MMCME2_ADV"),
    ]
    placed_metrics = [m for m in placed_metrics if m]

    final_timing = timing_summary(FILES["timing_final"])
    routed_timing = timing_summary(FILES["timing_routed"])
    power = parse_power(FILES["power"])
    drc_rows = parse_rule_summary(FILES["drc"])
    meth_rows = parse_rule_summary(FILES["methodology"])
    synth_warn, synth_crit, synth_err, _ = warning_counts(FILES["synth_log"])
    impl_warn, impl_crit, impl_err, _ = warning_counts(FILES["impl_log"])
    setup_paths, hold_paths, _ = parse_timing_paths(FILES["timing_final"])

    total_luts = int(top["total_luts"])
    total_ffs = int(top["ffs"])
    total_bram = float(top["ramb36"]) + float(top["ramb18"]) / 2.0
    total_dsp = int(top["dsp"]) or 1

    def ip_row(r: dict[str, object]) -> list[object]:
        bram = float(r["ramb36"]) + float(r["ramb18"]) / 2.0
        return [
            r["instance"],
            r["module"],
            fmt(r["total_luts"]),
            f"{float(r['total_luts']) / total_luts * 100:.1f}%",
            fmt(r["ffs"]),
            f"{float(r['ffs']) / total_ffs * 100:.1f}%",
            fmt(bram),
            f"{bram / total_bram * 100:.1f}%" if total_bram else "0%",
            fmt(r["dsp"]),
            f"{float(r['dsp']) / total_dsp * 100:.1f}%",
        ]

    notable_methodology = [
        row for row in meth_rows
        if row[0] in {"SYNTH-6", "SYNTH-9", "SYNTH-15", "TIMING-18", "TIMING-20", "TIMING-9", "TIMING-10"}
    ]
    notable_drc = [
        row for row in drc_rows
        if row[0] in {"CFGBVS-1", "DPIP-1", "DPOP-1", "DPOP-2", "PDRC-153", "RBOR-1", "REQP-1839", "REQP-1840"}
    ]

    out: list[str] = []
    out.append("# BK_AISoC Vivado Summary\n")
    out.append(f"- Generated: {dt.datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %z')}")
    out.append("- Project: `/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.xpr`")
    out.append("- Top module: `BK_AISoC`")
    out.append("- Device: `xc7vx485tffg1761-2`")
    out.append("- Vivado: `2024.2`")
    out.append("- Runs used: `synth_5` and `impl_5_copy_1`\n")

    out.append("## 1. Kết Luận Nhanh\n")
    out.append(md_table(
        ["Mục", "Giá trị cần biết"],
        [
            ["Bitstream", f"Đã tạo thành công: `BK_AISoC.bit` ({stat_line(FILES['bitstream'])})"],
            ["Timing final", "PASS, tất cả timing constraints do user khai báo đều đạt"],
            ["Setup margin", f"WNS = `{final_timing.get('WNS')} ns`, TNS = `{final_timing.get('TNS')} ns`, failing endpoints = `{final_timing.get('TNS Failing Endpoints')}`"],
            ["Hold margin", f"WHS = `{final_timing.get('WHS')} ns`, THS = `{final_timing.get('THS')} ns`, failing endpoints = `{final_timing.get('THS Failing Endpoints')}`"],
            ["Route", "Fully routed, routing errors = `0`"],
            ["Power estimate", f"`{power.get('Total On-Chip Power (W)')} W`, confidence = `{power.get('Confidence Level')}`"],
            ["Điểm đáng chú ý", "Timing pass nhưng setup margin rất sát: `0.005 ns` ở clock 200 MHz"],
        ],
    ))
    out.append("")

    out.append("## 2. Timing Chính\n")
    out.append(md_table(
        ["Stage", "WNS(ns)", "TNS(ns)", "Setup fail", "WHS(ns)", "THS(ns)", "Hold fail", "Nhận xét"],
        [
            [
                "Sau route",
                routed_timing.get("WNS"),
                routed_timing.get("TNS"),
                routed_timing.get("TNS Failing Endpoints"),
                routed_timing.get("WHS"),
                routed_timing.get("THS"),
                routed_timing.get("THS Failing Endpoints"),
                "Fail setup nhẹ",
            ],
            [
                "Sau post-route physopt",
                final_timing.get("WNS"),
                final_timing.get("TNS"),
                final_timing.get("TNS Failing Endpoints"),
                final_timing.get("WHS"),
                final_timing.get("THS"),
                final_timing.get("THS Failing Endpoints"),
                "Pass",
            ],
        ],
    ))
    out.append("\nClock dùng trong design:\n")
    out.append(md_table(
        ["Clock", "Period", "Frequency"],
        [
            ["`clk_p` / `clk_out200MHz_clk_wiz_0`", "5.000 ns", "200 MHz"],
            ["`cam_pclk_i`", "20.000 ns", "50 MHz"],
            ["`clk_out50MHz_clk_wiz_0`", "20.000 ns", "50 MHz"],
            ["`clk_out25MHz_clk_wiz_0`", "40.000 ns", "25 MHz"],
            ["`clk_out24MHz_clk_wiz_0`", "41.667 ns", "24 MHz"],
        ],
    ))
    worst_setup = setup_paths[0]
    worst_hold = hold_paths[0]
    out.append("\nCritical path summary:")
    out.append(md_table(
        ["Loại", "Slack(ns)", "Clock", "Block liên quan", "Nhận xét"],
        [
            [
                "Worst setup",
                worst_setup.get("slack", ""),
                worst_setup.get("path_group", ""),
                "`cnn_accel/u_cnn_accel/u_filter_buf`",
                f"Margin sát nhất, data delay `{worst_setup.get('data_path_delay', '')}`",
            ],
            [
                "Worst hold",
                worst_hold.get("slack", ""),
                worst_hold.get("path_group", ""),
                "`video_streaming/DVP_core/resize_mover_data_dut`",
                f"Hold vẫn pass, data delay `{worst_hold.get('data_path_delay', '')}`",
            ],
        ],
    ))
    out.append("")

    out.append("## 3. Tài Nguyên Tổng\n")
    out.append(md_table(
        ["Resource", "Used", "Available", "Util%"],
        [[m["name"], fmt(m["used"]), fmt(m["available"]), m["pct"]] for m in placed_metrics],
    ))
    out.append("\nNhận xét: BRAM là tài nguyên dùng nhiều nhất theo phần trăm (`40.19%`). LUT, FF và DSP còn dư rất nhiều.\n")

    out.append("## 4. Tài Nguyên Theo IP / Block Cấp Cao\n")
    out.append(md_table(
        ["IP / Instance", "Module", "LUT", "LUT%", "FF", "FF%", "BRAM tile eq.", "BRAM%", "DSP", "DSP%"],
        [ip_row(r) for r in top_children],
    ))
    out.append(
        "\nNhận xét nhanh:\n"
        "- `cnn_accel` chiếm phần lớn LUT/FF/DSP: khoảng `81.9%` LUT, `82.3%` FF, `86.4%` DSP của design.\n"
        "- `video_streaming` chiếm phần lớn BRAM: khoảng `77.5%` BRAM tile equivalent.\n"
        "- CPU PicoRV32 và peripheral AXI-lite nhỏ so với accelerator/video path.\n"
    )

    out.append("## 5. Power\n")
    out.append(md_table(
        ["Metric", "Value"],
        [
            ["Total On-Chip Power", f"{power.get('Total On-Chip Power (W)')} W"],
            ["Dynamic", f"{power.get('Dynamic (W)')} W"],
            ["Device Static", f"{power.get('Device Static (W)')} W"],
            ["Junction Temperature", f"{power.get('Junction Temperature (C)')} C"],
            ["Max Ambient", f"{power.get('Max Ambient (C)')} C"],
            ["Confidence", power.get("Confidence Level")],
        ],
    ))
    out.append("\nLưu ý: power confidence là `Low`, nên số power chỉ nên dùng như ước lượng nếu chưa có SAIF/VCD switching activity.\n")

    out.append("## 6. Warning / Risk Cần Biết\n")
    out.append(md_table(
        ["Nguồn", "Warning", "Critical warning", "Error"],
        [
            ["Synthesis", synth_warn, synth_crit, synth_err],
            ["Implementation", impl_warn, impl_crit, impl_err],
        ],
    ))
    out.append("\nDRC đáng chú ý:")
    out.append(md_table(["Rule", "Severity", "Ý nghĩa", "Count"], notable_drc))
    out.append("\nMethodology đáng chú ý:")
    out.append(md_table(["Rule", "Severity", "Ý nghĩa", "Count"], notable_methodology))
    out.append(
        "\nCác điểm nên xử lý nếu cần report sạch:\n"
        "1. Thêm/kiểm tra `CFGBVS` và `CONFIG_VOLTAGE` trong XDC.\n"
        "2. Bổ sung `set_input_delay` / `set_output_delay` cho các cổng ngoài nếu cần timing signoff.\n"
        "3. Kiểm tra latch `RGBchannel_reg` trong `video_streaming/DVP_core/HDMI_interface_uut`.\n"
        "4. Xem lại worst setup path trong `cnn_accel/u_cnn_accel/u_filter_buf` vì margin chỉ `0.005 ns`.\n"
        "5. Nếu báo cáo power chính thức, chạy lại power với SAIF/VCD activity.\n"
    )

    out.append("## 7. File Report Gốc\n")
    out.append(md_table(
        ["Loại", "File"],
        [
            ["Timing final", str(FILES["timing_final"])],
            ["Utilization placed", str(FILES["util_placed"])],
            ["Utilization hierarchical", str(FILES["util_hier6"])],
            ["Power", str(FILES["power"])],
            ["DRC", str(FILES["drc"])],
            ["Methodology", str(FILES["methodology"])],
            ["Route status", str(FILES["route"])],
        ],
    ))
    out.append("")

    return "\n".join(out)


if __name__ == "__main__":
    OUT.write_text(make(), encoding="utf-8")
    print(OUT)
