# Contributing to Skyjoust

Contributions, bug fixes, and gameplay polish PRs are welcome.

## Development Workflow

1. Fork the repository and create a feature branch off `main`.
2. Run the headless Godot 4.7+ verification suites before opening a pull request:
   ```bash
   godot --headless --path game -s res://tests/test_all.gd
   godot --headless --path game -s res://tests/tests_hand.gd
   godot --headless --path game -s res://tests/tests_crumble.gd
   godot --headless --path game -- --sim=300
   ```
3. Keep gameplay logic in the deterministic 2D coordinate plane (`rng` isolated from `vis_rng`) so `--sim` runs remain reproducible and exit with zero leaked resources or warnings.
4. If modifying `docs/` showcase assets, verify all relative links and run `python3 tools/verify_repo.py`.
