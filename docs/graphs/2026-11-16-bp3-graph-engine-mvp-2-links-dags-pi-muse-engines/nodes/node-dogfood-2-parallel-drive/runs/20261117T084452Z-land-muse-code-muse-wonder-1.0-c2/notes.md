# Land run notes

- Claimed one-time link bp3link_195d3c231302a18528d589d37330947a; run_id matches expected 20261117T084452Z-land-muse-code-muse-wonder-1.0-c2.
- Verified run folder did not exist before creation (no E_RUN_EXISTS collision).
- Created run folder and tape.log verbatim evidence; all subsequent shell output appended via tee.
- Landing exp-dogfood-2-parallel-drive from approved at cycle 2 via direct `bp3 q u ... land` with BP3_RUN_ID stamped.
- Lesson: claim first, check collision, keep tape verbatim only — never parse tape into facts; verdict comes from the land call JSON.
