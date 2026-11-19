# Land run notes — node-dogfood-3-external-drive

- Claimed one-time link bp3link_3887ddfca231cd4119b778f753276eed; run_id matched expected 20261118T144632Z-land-muse-code-muse-wonder-1.0-c1.
- Run folder did not pre-exist; created fresh (fail-if-exists held).
- HEAD at land time: ac43954bd4e746115fc8761b3ce8f2fe95063c68 (dogfood.3 external-drive work).
- Node was in approved state at cycle 1; landing via direct `bp3 g u land` call from this child.
- Tape is verbatim evidence only.

Lesson: land children must claim first, create the run folder second, and call the edge themselves with BP3_RUN_ID stamped — never relay the verdict via the parent.
