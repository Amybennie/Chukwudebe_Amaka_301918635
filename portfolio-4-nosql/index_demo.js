// =============================================================================
// index_demo.js - Portfolio 4 (NoSQL / MongoDB)
// Student : Amaka Benedicta Chukwudebe
// Matric  : 2026/A/MIT/0517
// Course  : MIT 8103 Advanced Database Systems
// Cohort  : September 2026 (2026/2027 First Semester)
// Case    : CampusNest - Private Student Accommodation Booking
//
// Purpose
// -------
//   Demonstrate COLLSCAN (collection scan) before a supporting index is
//   created, and IXSCAN (index scan) after. We use explain('executionStats')
//   on a realistic query - "find all OPEN PLUMBING tickets at lodge_id=2
//   reported in the last 30 days" - and print the relevant fields the
//   student should screenshot for the LMS submission:
//
//     * executionStages.stage   ->  COLLSCAN before, IXSCAN after
//     * totalDocsExamined       ->  high before, low after
//     * executionTimeMillis     ->  longer before, shorter after
//     * nReturned               ->  matches the qualifying docs
//
// Run
// ---
//   mongosh mongodb://127.0.0.1:27017/campusnest_nosql index_demo.js
// =============================================================================
const db = db.getSiblingDB('campusnest_nosql');

print('\n============================================================');
print(' index_demo.js - COLLSCAN before, IXSCAN after');
print('============================================================\n');

// ---------------------------------------------------------------------------
// 0. Drop every secondary index on maintenance_tickets so the BEFORE step
//    really does COLLSCAN. The _id index is preserved automatically.
// ---------------------------------------------------------------------------
print('[0] Dropping all secondary indexes on maintenance_tickets ...');
db.maintenance_tickets.dropIndexes();
print('    Current indexes (should be just _id_):');
print('    ' + db.maintenance_tickets.getIndexes().map(function (i) { return i.name; }).join(', '));

// ---------------------------------------------------------------------------
// 1. The query we will explain twice. Realistic: a lodge manager opens the
//    maintenance dashboard filtered to "unfinished <category> tickets at my
//    lodge reported in the last 30 days". We pick the lodge + category that
//    really has the most unfinished tickets right now, so the query returns rows.
// ---------------------------------------------------------------------------
const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);
const busiest = db.maintenance_tickets.aggregate([
    { $match: { status: { $in: ['open', 'in_progress'] }, reported_at: { $gte: thirtyDaysAgo } } },
    { $group: { _id: { lodge_id: '$lodge_id', lodge_name: '$lodge_name', category: '$category' }, n: { $sum: 1 } } },
    { $sort: { n: -1, '_id.lodge_id': 1 } }, { $limit: 1 }
]).toArray()[0]._id;
print('\nDashboard for: ' + busiest.lodge_name + ' (lodge_id ' + busiest.lodge_id + '), category ' + busiest.category);

const query = {
    lodge_id:    busiest.lodge_id,
    status:      { $in: ['open', 'in_progress'] },
    category:    busiest.category,
    reported_at: { $gte: thirtyDaysAgo }
};

print('\nQuery:');
printjson(query);

// Helper - pull the useful bits out of a verbose explain() result so the
// screenshot is readable. We still print the full executionStats below.
function summarizeExplain(explain) {
    const stats = explain.executionStats || {};
    const stage = stats.executionStages || {};
    return {
        winningPlan_stage:        stage.stage,
        totalDocsExamined:        stats.totalDocsExamined,
        totalKeysExamined:        stats.totalKeysExamined,
        nReturned:                stats.nReturned,
        executionTimeMillis:      stats.executionTimeMillis,
        executionStages_stage:    stage.stage,
        executionStages_direction: stage.direction,
        executionStages_nReturned: (stage.nReturned || null),
        executionStages_docsExamined: (stage.docsExamined || null)
    };
}

// ---------------------------------------------------------------------------
// 2. BEFORE INDEX - expect COLLSCAN.
// ---------------------------------------------------------------------------
print('\n===== BEFORE INDEX - expect COLLSCAN =====');

const explainBefore = db.maintenance_tickets
    .find(query)
    .explain('executionStats');

print('\n-- Summarised executionStats (before) --');
const beforeSummary = summarizeExplain(explainBefore);
printjson(beforeSummary);

// (full executionStats omitted to keep the log readable; the summary above has the key numbers)

// ---------------------------------------------------------------------------
// 3. Create the supporting compound index.
//
//    ESR rule (Equality, Sort, Range):
//      lodge_id   = equality
//      status     = equality
//      category   = equality
//      reported_at >= range
//
//    Compound order: equality keys first (lodge_id, status, category), then
//    the range key last (reported_at descending so the newest ticket is
//    returned first).
// ---------------------------------------------------------------------------
print('\n[3] Creating compound index:');
print('    { lodge_id:1, status:1, category:1, reported_at:-1 }');
db.maintenance_tickets.createIndex(
    { lodge_id: 1, status: 1, category: 1, reported_at: -1 },
    { name: 'idx_lodge_status_cat_reported' }
);

print('    Indexes now:');
print('    ' + db.maintenance_tickets.getIndexes().map(function (i) { return i.name; }).join(', '));

// ---------------------------------------------------------------------------
// 4. AFTER INDEX - expect IXSCAN.
// ---------------------------------------------------------------------------
print('\n===== AFTER INDEX - expect IXSCAN =====');

const explainAfter = db.maintenance_tickets
    .find(query)
    .explain('executionStats');

print('\n-- Summarised executionStats (after) --');
const afterSummary = summarizeExplain(explainAfter);
printjson(afterSummary);



// ---------------------------------------------------------------------------
// 5. Side-by-side comparison so the screenshot shows the win clearly.
// ---------------------------------------------------------------------------
print('\n===== COMPARISON (real values from this run) =====');
print('  Metric                   | BEFORE            | AFTER');
print('  -------------------------|-------------------|-------------------');
print('  executionStages.stage    | ' + beforeSummary.executionStages_stage + ' | ' + afterSummary.executionStages_stage);
// FETCH sits on top of the index scan; show the stage underneath it too.
const afterInput = (explainAfter.executionStats.executionStages.inputStage || {});
print('  stage under FETCH        | -        | ' + (afterInput.stage || '-') + ' on ' + (afterInput.indexName || '-'));
print('  totalDocsExamined        | ' + beforeSummary.totalDocsExamined + ' | ' + afterSummary.totalDocsExamined);
print('  totalKeysExamined        | ' + beforeSummary.totalKeysExamined + ' | ' + afterSummary.totalKeysExamined);
print('  nReturned                | ' + beforeSummary.nReturned + ' | ' + afterSummary.nReturned);
print('  executionTimeMillis      | ' + beforeSummary.executionTimeMillis + ' | ' + afterSummary.executionTimeMillis);

print('\n============================================================');
print(' index_demo.js DONE.');
print('============================================================\n');
