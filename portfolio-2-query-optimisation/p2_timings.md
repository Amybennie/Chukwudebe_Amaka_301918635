# Portfolio 2 - real before/after timings

Built automatically by run_p2.sh from explain_before.log and explain_after.log (this run, this Codespace). Times are single runs and vary a little between runs.

| Query | Before: scans used | Before ms | After: scans used | After ms | Change |
|---|---|---|---|---|---|
| Q1 free rooms | Seq Scan on lodge; Bitmap Index Scan on room_lodge_id_room_code_key; Index Scan using tenancy_no_room_overlap on tenancy; Index Scan using room_type_pkey on room_type | 1.713 | Seq Scan on lodge; Index Scan using idx_room_lodge_id on room; Index Scan using idx_tenancy_room_id on tenancy; Index Scan using room_type_pkey on room_type | 0.718 | 58% faster |
| Q2 occupancy pct | Seq Scan on tenancy; Seq Scan on room; Seq Scan on lodge | 24.676 | Bitmap Index Scan on idx_tenancy_start_end; Seq Scan on room; Seq Scan on lodge | 12.792 | 48% faster |
| Q3 rent collected vs outstanding | Seq Scan on rent_instalment; Seq Scan on tenancy; Seq Scan on room; Seq Scan on lodge | 133.523 | Seq Scan on rent_instalment; Seq Scan on tenancy; Seq Scan on room; Seq Scan on lodge | 111.931 | 16% faster |
| Q4 tenants with overdue instalments | Seq Scan on rent_instalment; Seq Scan on tenancy; Seq Scan on room; Seq Scan on lodge; Seq Scan on tenant | 34.212 | Seq Scan on tenancy; Index Scan using idx_rent_instalment_overdue on rent_instalment; Seq Scan on room; Seq Scan on lodge; Seq Scan on tenant | 26.235 | 23% faster |
| Q5 waitlist length per room type | Seq Scan on waitlist_entry; Seq Scan on room_type; Seq Scan on lodge | 0.793 | Seq Scan on waitlist_entry; Seq Scan on room_type; Seq Scan on lodge | 0.793 | 0% slower |
| Q6 avg days to fix maintenance ticket | Seq Scan on maintenance_ticket; Seq Scan on lodge | 1.755 | Seq Scan on maintenance_ticket; Seq Scan on lodge | 1.745 | 1% faster |
| Q7 student history by matric | Index Scan using tenant_pkey on tenant; Index Scan using tenancy_pkey on tenancy; Seq Scan on rent_instalment; Seq Scan on tenancy; Seq Scan on tenant; Index Scan using room_pkey on room; Index Scan using lodge_pkey on lodge | 25.499 | Index Scan using tenant_pkey on tenant; Index Scan using tenancy_pkey on tenancy; Index Scan using idx_tenant_matric on tenant; Index Scan using idx_tenancy_tenant_id on tenancy; Index Scan using room_pkey on room; Index Scan using lodge_pkey on lodge; Index Scan using idx_rent_instalment_tenancy_id on rent_instalment | 0.166 | 99% faster |
