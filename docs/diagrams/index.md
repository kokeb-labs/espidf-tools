# Figures

<!-- Written by kokeb-docs figures from docs/diagrams/figures/*.py. Do not edit by hand. -->

Every figure on this site is drawn by a Python module from facts extracted from the code, so it is rebuilt,
not redrawn, when the code changes. CI runs `kokeb-docs figures --check` and fails when a
committed figure no longer matches the code. Each figure below lists the files it is drawn from.

## Two ways in, one configuration file

<!-- figure: tool-map -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="tool-map.dark.svg">
  <img src="tool-map.svg"
    alt="Diagram: you run the commands, or ru-build runs generate_matrix.py and then build_app.sh in CI; the
    commands load settings through config_loader.sh, build_app.sh asks get_app_info.py for the source
    file, the commands run idf.py, and config_loader.sh, get_app_info.py and generate_matrix.py all read
    app_config.yml.">
</picture>
<!-- /figure -->

Figure module: [`docs/diagrams/figures/tool-map.py`](../../docs/diagrams/figures/tool-map.py)

Drawn from:

- `source config_loader.sh` in [`build_app.sh`](../../build_app.sh)
- `source config_loader.sh` in [`flash_app.sh`](../../flash_app.sh)
- `source config_loader.sh` in [`manage_idf.sh`](../../manage_idf.sh)
- `source config_loader.sh` in [`idf_flash_monitor.sh`](../../idf_flash_monitor.sh)
- `get_app_info.py` in [`build_app.sh`](../../build_app.sh)
