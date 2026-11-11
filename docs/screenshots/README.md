# Evidence to capture (from your own Codespace run)

Every log below is written by the scripts when YOU run them. `collect_results.sh`
copies them into `my_results.txt`. Screenshots, if you take any, must be of
your own terminal.

| Portfolio | File | What it shows |
|---|---|---|
| P1 | `portfolio-1-database-design/p1_output.log` | schema + seed loaded, bulk generator summary (50,000+ tenancies), 9 of 9 constraint tests PASS, row counts |
| P2 | `portfolio-2-query-optimisation/p2_timings.md`, `explain_before.log`, `explain_after.log` | before/after plans and times for Q1-Q7 |
| P3 | `portfolio-3-transactions-concurrency/p3_output.log`, `race_demos_output.log` | COMMIT and ROLLBACK demos; the six two-session scenarios |
| P4 | `portfolio-4-nosql/p4_output.log`, `index_demo_output.log` | validator rejecting a bad document, 42,000 tickets, three aggregations, COLLSCAN -> IXSCAN |
| P5 | `portfolio-5-distributed-cloud/p5_output.log`, `replication_output.log` | rows per session partition, partition pruning, replica proof |
