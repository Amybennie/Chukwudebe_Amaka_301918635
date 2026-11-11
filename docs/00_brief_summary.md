# 00 - Brief Summary

**Student:** Amaka Benedicta Chukwudebe
**Matric:** 2026/A/MIT/0517
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 - Advanced Database Systems
**Cohort:** September 2026 (2026/2027 First Semester)
**Case study:** CampusNest - Private Student Accommodation Booking

---

## (a) What the CA requires

This section summarises the Continuous Assessment brief in
`mit-8103-advanced-database-systems-ca-september-cohort-2026.pdf`. It is a
plain-English reading of the brief; the PDF remains the authoritative source.

### Assessment type and weight
- **Type:** Individual Practical Database Portfolio (not a written essay).
- **Weight:** 40 marks for the portfolio + final documentation, distributed as below.
- **Mode:** Submission on the LMS + a private GitHub repository.

### Portfolio components and marks

| Portfolio | Activity | Marks |
|-----------|----------|-------|
| 1 | Database Design and Modelling | 7 |
| 2 | Query Processing and Optimisation | 7 |
| 3 | Transactions and Concurrency | 7 |
| 4 | NoSQL and Advanced Data Models | 7 |
| 5 | Distributed and Cloud Database Exercise | 6 |
| Final | Documentation and technical reflection | 6 |
| **Total** | | **40** |

### Marking rubric (Section 9 of the brief)

| Criterion | Marks |
|-----------|-------|
| Technical correctness | 8 |
| Database design quality | 6 |
| Practical implementation | 8 |
| Query and performance analysis | 5 |
| Application of advanced database concepts | 5 |
| Documentation and GitHub organisation | 5 |
| Technical reflection / evidence of individual understanding | 3 |
| **Total** | **40** |

### Deliverables

1. **Five portfolios**, each with practical evidence (SQL scripts, schemas, ER diagrams, NoSQL implementations, execution plans, screenshots, configuration files, test results, README files).
2. **A private GitHub repository** named `advanced-database-portfolio/` with the suggested folder structure:
   ```
   advanced-database-portfolio/
   ├── portfolio-1-database-design/
   ├── portfolio-2-query-optimisation/
   ├── portfolio-3-transactions-concurrency/
   ├── portfolio-4-nosql/
   ├── portfolio-5-distributed-cloud/
   └── README.md
   ```
3. **A 2-3 page documentation** submitted through the LMS describing all five portfolios, the selected case study, the GitHub link, supporting screenshots/evidence, an individual technical reflection, and references / AI-use declaration.

### Page limit
- **2-3 pages** for the LMS documentation file (Section 6 of the brief). The portfolios themselves have no page limit; they are judged by practical evidence.

### Naming rules
- The CA brief does **not** prescribe a filename convention. The student has elected to use the matric-number convention requested in the cohort instructions:
  - Final documentation: `Chukwudebe_Amaka_2026-A-MIT-0517_Documentation.pdf`
  - GitHub repository: `advanced-database-portfolio` (matches Section 5 of the brief).
  - Portfolio folders: `portfolio-1-database-design` ... `portfolio-5-distributed-cloud` (matches the brief's suggested structure).

### Submission rules (Sections 5, 6, 12)
- **GitHub:** Create a **private** repository; commit progressively throughout the semester (not all at the deadline). The assessor must be able to access it before LMS submission.
- **LMS:** Submit the 2-3 page documentation plus supporting screenshots/evidence.
- **Checklist (Section 12):** case study clearly stated; all five portfolios complete and consistent with the case study; repository organised; practical evidence included; README explains the work; GitHub link works; sources/datasets/libraries referenced; AI use declared; individual technical reflection included; student can explain the work if selected for verification.

### AI use (Section 11)
- AI tools are **permitted as learning aids**, but the student remains responsible for accuracy, originality, and understanding.
- An **AI Use Declaration** must state: (i) the AI tool used, (ii) what it was used for, (iii) how the output was reviewed, corrected, tested, or verified.
- This declaration goes into the final documentation file, not into the individual portfolio folders. The student will fill it in after running everything.

### Similarity / academic integrity (Sections 7, 11)
- This is **individual work**. Students may discuss general concepts with colleagues, but the implementation, scripts, analysis, documentation, and conclusions must be their own.
- The brief does **not** state a numeric similarity threshold (e.g. a Turnitin percentage). It instead relies on: progressive GitHub commits, clear READMEs, real screenshots/outputs/logs, a short individual reflection, and the lecturer's right to invite a small sample of students for a brief technical verification discussion (Section 8). Submissions that are "unclear, copied, inaccessible, or suspicious" may be flagged.
- Practical implication for this portfolio: every result placeholder in this repository is the literal string `[paste real output here]` until the student runs the work and pastes the real output. Nothing is fabricated.

### Individual verification (Section 8)
- Because the cohort is large, there is **no compulsory viva**. Verification relies on submitted technical evidence, structured documentation, and progressive GitHub activity.
- The lecturer may select a small sample of students for a brief technical verification discussion. Students must therefore be able to explain every script, query, and design choice they submit.

---

## (b) Portfolio -> course-note study session map

The course notes (`Edited - MIT8103 Advanced Database Systems.pdf`, 154 pages, Miva Open University) are organised into **six study sessions**:

| # | Study session | Topics |
|---|---------------|--------|
| 1 | Review of Traditional Relational Databases and Advanced Concepts | Database system design stages; types of DB systems; DBMS components; characteristics of a good database; normalisation; limitations of traditional DBMS |
| 2 | Distributed Database System | DDBS architecture; peer-peer, client-server, federated; data fragmentation, replication, consistency models; CAP theorem; BASE vs ACID |
| 3 | Big Data and Cloud Database Systems | Big data; cloud database systems and use cases; data warehouse; database security |
| 4 | Query Optimisation in Database | Introduction to queries; query optimisation; query execution plans and cost estimation; file organisation |
| 5 | Emerging Trends in Database Systems | DB evolution; AI-powered databases; blockchain and distributed DBs; edge databases; serverless databases; graph databases and knowledge graphs |
| 6 | Introduction to Data Security and Data Privacy | Data privacy; advanced quantitative techniques; challenges of ensuring data privacy; best practices for implementing data privacy |

### Mapping

| Portfolio | Primary study session(s) | Why |
|-----------|--------------------------|-----|
| **P1 - Database Design and Modelling** | **Study Session 1** (Review of Traditional Relational Databases and Advanced Concepts) | The ER diagram, relational schema, keys, constraints, and 3NF normalisation explanation are exactly the normalisation and database design topics of Session 1. The exclusion constraints and triggers are the "advanced concepts" half of Session 1. |
| **P2 - Query Processing and Optimisation** | **Study Session 4** (Query Optimisation in Database) | The six queries, the EXPLAIN ANALYZE before/after indexes, the cost estimation reading, and the file-organisation note (sequential vs index scan) map directly onto Session 4's "query execution plans and cost estimation" and "file organisation in database". |
| **P3 - Transactions and Concurrency** | **Study Session 1** (advanced concepts - ACID) + **Study Session 2** (consistency models, BASE vs ACID) | The reserve_room() transaction demonstrates COMMIT/ROLLBACK and ACID (Session 1 advanced concepts). The race condition, SELECT ... FOR UPDATE SKIP LOCKED, isolation levels, and deadlock demo are the consistency-model and concurrency material that Session 2 builds on top of ACID. |
| **P4 - NoSQL and Advanced Data Models** | **Study Session 3** (Big Data and Cloud Database Systems) + **Study Session 5** (Emerging Trends - graph DB, serverless) | MongoDB is a document store that scales to big-data volumes (Session 3's big-data topic). The schema-validation + flexible-per-category maintenance tickets illustrate the "emerging trends" departure from rigid relational schemas that Session 5 documents. The SQL-vs-NoSQL comparison closes the loop on when each model fits. |
| **P5 - Distributed and Cloud Database Exercise** | **Study Session 2** (Distributed Database System - replication, CAP, consistency) + **Study Session 3** (Cloud Database Systems) + **Study Session 6** (Data Security and Data Privacy) | The monthly partitioning + primary/streaming read replica is the distributed-DB architecture and replication material of Session 2. The cloud architecture keeping data in Nigeria under NDPA 2023 is the cloud-database and database-security material of Session 3 plus the data-privacy best practices of Session 6. The CAP and sync-vs-async trade-off discussion is straight out of Session 2. |

### Visual map

```
Study Session 1  ──>  P1 (design, 3NF, constraints)
                  ──\
                     >──  P3 (ACID + concurrency + consistency)
Study Session 2  ─────/

Study Session 3  ──>  P4 (big-data document store)
                  ──\
                     >──  P5 (cloud DB + replication + security)
Study Session 2  ──/
Study Session 6  ──/

Study Session 4  ──>  P2 (query optimisation, execution plans)

Study Session 5  ──>  P4 (emerging data models - flexible schema)
```

---

## What this repository contains (and what it does NOT)

**Contains**
- `setup.sh` - installs PostgreSQL 16 + MongoDB 8 in Codespaces.
- `README.md` - repo overview, case study, run instructions, `[GitHub link]` placeholder.
- `docs/00_brief_summary.md` - this file.
- `portfolio-1-database-design/` through `portfolio-5-distributed-cloud/` - complete files for each portfolio, each with its own `README.md`, `run_pN.sh`, SQL/JS scripts, and notes.

**Does NOT contain (yet)**
- `Chukwudebe_Amaka_2026-A-MIT-0517_Documentation.pdf` - the 2-3 page LMS documentation. By the student's explicit instruction, this is produced **after** all five portfolios have been run and the real results pasted in. It will include the GitHub link, the individual reflection, and the AI-use declaration.
- Any real EXPLAIN plans, timings, or screenshot outputs. Where these would appear, the literal placeholder `[paste real output here]` is used. This is the honesty rule: nothing is fabricated.
