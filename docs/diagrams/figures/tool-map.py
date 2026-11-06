"""Who runs what, and where every script gets its settings: one app_config.yml.

Reads: Top to bottom, from who starts the work to the file everything reads. There are two ways in: you run a
command in a terminal, or ci-tools' ru-build runs in CI. The commands (read from the scripts that source
config_loader.sh) load their settings through config_loader.sh; build_app.sh also asks get_app_info.py for an
app's source file, and the build and flash commands run idf.py. In CI, ru-build first runs generate_matrix.py to
get one job per app, ESP-IDF version and build type, then runs build_app.sh in each job. config_loader.sh,
get_app_info.py and generate_matrix.py all read the same app_config.yml. Solid arrows run something, dashed
arrows read a file.
"""

import re

from kokeb_mkdocs_theme.figkit import Fig
from kokeb_mkdocs_theme.paths import repo_root

ROOT = repo_root()
COMMANDS = ["build_app.sh", "flash_app.sh", "manage_idf.sh", "idf_flash_monitor.sh", "setup_repo.sh",
            "setup_basic.sh", "manage_logs.sh", "detect_ports.sh"]


def data():
    users = [s for s in COMMANDS
             if re.search(r'source\s+"?\$(?:SCRIPT_DIR|script_dir)/config_loader\.sh', (ROOT / s).read_text())]
    info = "get_app_info.py" in (ROOT / "build_app.sh").read_text()
    return {
        "commands": COMMANDS,
        "sources_config_loader": users,
        "build_app_uses_get_app_info": info,
        "sources": [f"{s}:source config_loader.sh" for s in users] + ["build_app.sh:get_app_info.py"],
    }


def build(d):
    f = Fig(
        "tool-map",
        "Two ways in, one configuration file",
        alt="Diagram: you run the commands, or ru-build runs generate_matrix.py and then build_app.sh in CI; the "
        "commands load settings through config_loader.sh, build_app.sh asks get_app_info.py for the source file, "
        "the commands run idf.py, and config_loader.sh, get_app_info.py and generate_matrix.py all read "
        "app_config.yml.",
        width=1200,
        kicker="Tools",
        subtitle="Apps, ESP-IDF versions, build types and target are written once, in app_config.yml.",
        profile="overview",
        legend=[("teal", "yours"), ("brand", "script in espidf-tools"), ("slate", "ESP-IDF and CI"),
                ("~solid", "runs"), ("~dashed", "reads")],
    )
    W = f.body_w
    gap, row = 72, 64
    cw = (W - 2 * gap) / 3
    cx = [0, cw + gap, 2 * (cw + gap)]
    H = 92

    you = f.card(cx[0], 0, cw, "You, in a terminal", ["build, flash, monitor"], tone="teal", accent=True, h=H)
    ci = f.card(cx[2], 0, cw, "ci-tools ru-build", ["on every push"], tone="slate", accent=True, h=H)

    top = you.b + row
    inner = f.region_inner_top(top)
    chips = f.chips(16, inner, 2 * cw + gap - 32, d["sources_config_loader"], tone="brand", on="brand.tint")
    reg = f.region(0, top, 2 * cw + gap, max(inner - top + chips + 18, 116), "Commands", tone="brand")
    gen = f.card(cx[2], top, cw, "generate_matrix.py", ["one CI job per app,", "IDF version, build type"],
                 tone="brand", accent=True, h=reg.h)

    y3 = reg.b + row
    loader = f.card(cx[0], y3, cw, "config_loader.sh", ["yq, or a grep fallback"], tone="brand", accent=True, h=H)
    narrow = cw - 64
    info = f.card(cx[1], y3, narrow, "get_app_info.py", ["an app's source file"], tone="brand", accent=True, h=H)
    idf = f.card(cx[2], y3, narrow, "idf.py", ["ESP-IDF in ~/esp"], tone="slate", accent=True, h=H)

    cfg = f.card(0, loader.b + row, W, "app_config.yml",
                 ["apps, ESP-IDF versions, build types and target, in your ESP-IDF project"], tone="teal", accent=True)

    # Who runs what.
    f.edge([(you.cx, you.b + 4), (you.cx, reg.y - 4)], label="run")
    f.edge([(ci.cx, ci.b + 4), (ci.cx, gen.y - 4)], label="1 first")
    xr = reg.x + reg.w * 0.82
    f.edge([(ci.x - 4, ci.cy), (xr, ci.cy), (xr, reg.y - 4)], label="2 then build_app.sh", label_at=0.3)
    f.edge([(loader.cx, reg.b + 4), (loader.cx, loader.y - 4)], label="source")
    if d["build_app_uses_get_app_info"]:
        f.edge([(info.cx, reg.b + 4), (info.cx, info.y - 4)], label="build_app.sh")
    xi = reg.x + reg.w * 0.95
    f.edge([(xi, reg.b + 4), (xi, idf.cy), (idf.x - 4, idf.cy)])

    # Who reads the configuration.
    for box in (loader, info):
        f.edge([(box.cx, box.b + 4), (box.cx, cfg.y - 4)], dashed=True, label="reads")
    xg = gen.x + gen.w * 0.9
    f.edge([(xg, gen.b + 4), (xg, cfg.y - 4)], dashed=True, label="reads", label_at=0.25)
    return f
