# followup.6 check-tiers — land run notes (cycle 1)

Land stance: node read back `approved` at cycle 1 with legal edge
`land`; bound commit 0f60c7a50a826ca932a99c0097a2baf7ac227877.

- Grade (bound commit): ship — selector lists match all four
  mappings, sweep ok in 0.076s, `make check-fast` 54.7s, full
  `make check` recipe byte-identical, no suite weakened.
- Verify (fresh, this cycle): `make check-fast` exit 0 in 53.795s;
  full `make check` exit 0 in 6m40.816s; planted QUEST.md probe
  fails naming skills/demo/SKILL.md:1.
- Land smoke (fresh, this run): `./test/check-tiers.sh` ok
  (14 assertions) at HEAD 0f60c7a.
- This land commits the outstanding node/grade/verify run notes
  verbatim, mirroring the followup.5 c4 land pattern; tape.log
  files stay gitignored evidence.

## Lesson

Landing needs no new verification budget: grade quoted the suite
lists and verify re-ran both tiers fresh, so a seconds-long tier
test at the bound commit is the right land-time smoke.
