# Proposed ownership cleanup — approval pending

No moves have been performed. H-02 owns data/; the two files listed below were added by H-02 under H-03-owned tests/. The user requested agreement before correcting that cross-owner change. AGENTS.md / CONTRACT.yaml require writes to stay within the checked-out task's owns paths.

Proposed atomic change after approval:

1. Move tests/validate_schema.py to data/validate_schema.py. Change its data lookup from Path(__file__).resolve().parents[1] / 'data' to Path(__file__).resolve().parent, preserving operation from any working directory.
2. Move tests/expected_results.md to data/expected_results.md. Clearly label it as documentation of independent arithmetic examples, not measured large-scenario outputs. Link to audit/README.md for the actual b07d1a3 scenario results.
3. Update data/run_h02.command and data/README.md to run/reference the new schema validator path. Check remaining H-02 references and update them within data/. Update this proposal and the audit's pending-status text when approved.
4. Leave all H-03/H-04 tests, fixtures, app code and statistical functions untouched. The merged methods rule keeping formula test fixtures in tests/ continues to apply to the actual H-03 tests; no actual H-03 fixture is moved.
5. Run the moved schema validator from both the repository root and another working directory, check the launcher syntax, and verify unchanged generator/CSV hashes. Commit on h02-dataset and report the exact commit ID.

This proposal does not authorize changing seeds, data values, chart limits, timestamp formatting or the statistical design. Timestamp compatibility needs its own reviewed decision. H-02 remains in_progress until its unresolved findings and acceptance review are addressed.
