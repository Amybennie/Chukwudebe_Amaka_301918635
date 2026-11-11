// =============================================================================
// aggregations.js - Portfolio 4 (NoSQL / MongoDB)
// Student : Amaka Benedicta Chukwudebe
// Matric  : 2026/A/MIT/0517
// Course  : MIT 8103 Advanced Database Systems
// Cohort  : September 2026 (2026/2027 First Semester)
// Case    : CampusNest - Private Student Accommodation Booking
//
// Purpose
// -------
//   Run three business-question aggregations over the maintenance_tickets
//   collection and pretty-print the result of each. The student is expected
//   to run this file, copy the real output, and paste it into README.md at
//   the literal placeholder `[paste real output here]`.
//
//   AGG-1 : Tickets per lodge per category            (matrix view)
//   AGG-2 : Average resolution time per category       (in days)
//   AGG-3 : Repeat problems per bed-space              (2+ same-category
//                                                     tickets in 12 months)
//
// Run
// ---
//   mongosh mongodb://127.0.0.1:27017/campusnest_nosql aggregations.js
// =============================================================================
const db = db.getSiblingDB('campusnest_nosql');

print('\n============================================================');
print(' aggregations.js - three business-question aggregations');
print('============================================================\n');

// ---------------------------------------------------------------------------
// AGG-1: Tickets per lodge per category.
//
//   Two variants are run:
//     (a) A flat matrix: $group by {lodge_name, category} then $sort by
//         lodge_name then category. Easy to read as a tabular cross-tab.
//     (b) A nested view: $group by lodge_name and $push an array of
//         {category, count} sub-documents per lodge.
// ---------------------------------------------------------------------------
print('\n===== AGG-1: Tickets per lodge per category =====');
print('Variant (a): flat matrix {lodge_name, category, count}');

const agg1a = db.maintenance_tickets.aggregate([
    {
        $group: {
            _id: { lodge_name: '$lodge_name', category: '$category' },
            count: { $sum: 1 }
        }
    },
    {
        $project: {
            _id: 0,
            lodge_name: '$_id.lodge_name',
            category:   '$_id.category',
            count: 1
        }
    },
    { $sort: { count: -1, lodge_name: 1 } },
    { $limit: 12 }          // 100 lodges x 4 categories = 400 rows; show the 12 biggest
]).toArray();

print('Result (variant a, 12 biggest lodge/category cells):');
agg1a.forEach(function (d) { print('  ' + JSON.stringify(d)); });

print('\nVariant (b): nested {lodge_name, categories:[{category,count}]}');

const agg1b = db.maintenance_tickets.aggregate([
    {
        $group: {
            _id: { lodge_name: '$lodge_name', category: '$category' },
            count: { $sum: 1 }
        }
    },
    {
        $group: {
            _id: '$_id.lodge_name',
            categories: {
                $push: { category: '$_id.category', count: '$count' }
            },
            total: { $sum: '$count' }
        }
    },
    {
        $project: {
            _id: 0,
            lodge_name: '$_id',
            categories: 1,
            total: 1
        }
    },
    { $sort: { total: -1 } },
    { $limit: 5 }           // the 5 lodges with the most tickets
]).toArray();

print('Result (variant b, 5 busiest lodges):');
agg1b.forEach(function (d) { print('  ' + JSON.stringify(d)); });

// ---------------------------------------------------------------------------
// AGG-2: Average resolution time per category (in days).
//
//   $match only tickets with a resolved_at (i.e. resolved or closed).
//   $project resolution_days = (resolved_at - reported_at) / 86400000 ms.
//   $group by category, $avg and $sum.
//   $sort by avg_days descending so the slowest-to-fix category is on top.
// ---------------------------------------------------------------------------
print('\n===== AGG-2: Average resolution time per category (days) =====');

const agg2 = db.maintenance_tickets.aggregate([
    { $match: { resolved_at: { $exists: true } } },
    {
        $project: {
            category: 1,
            resolution_days: {
                $divide: [
                    { $subtract: ['$resolved_at', '$reported_at'] },
                    86400000
                ]
            }
        }
    },
    {
        $group: {
            _id: '$category',
            avg_days: { $avg: '$resolution_days' },
            count:    { $sum: 1 }
        }
    },
    {
        $project: {
            _id: 0,
            category: '$_id',
            avg_days: { $round: ['$avg_days', 2] },
            count: 1
        }
    },
    { $sort: { avg_days: -1 } }
]).toArray();

print('Result:');
agg2.forEach(function (d) { print('  ' + JSON.stringify(d)); });

// ---------------------------------------------------------------------------
// AGG-3: Repeat problems per room (rooms with 3+ tickets of the same
//        category in the last 90 days).
//
//   $match reported_at within the last 90 days.
//   $group by {room_code, category}, count.
//   $match count >= 3 (repeat problems).
//   $sort by count desc, $limit 20 so the report fits on a screenshot.
// ---------------------------------------------------------------------------
print('\n===== AGG-3: Repeat problems per bed-space (2+ same-category in 12 months) =====');

const oneYearAgo = new Date(Date.now() - 365 * 86400000);

const agg3 = db.maintenance_tickets.aggregate([
    { $match: { reported_at: { $gte: oneYearAgo } } },
    {
        $group: {
            _id: { room_code: '$room_code', category: '$category' },
            count:       { $sum: 1 },
            lodge_name:  { $first: '$lodge_name' },
            last_reported_at: { $max: '$reported_at' }
        }
    },
    { $match: { count: { $gte: 2 } } },
    {
        $project: {
            _id: 0,
            room_code:    '$_id.room_code',
            category:     '$_id.category',
            lodge_name:   1,
            count:        1,
            last_reported_at: 1
        }
    },
    { $sort: { count: -1, room_code: 1 } },
    { $limit: 20 }
]).toArray();

print('Result (top 20):');
agg3.forEach(function (d) { print('  ' + JSON.stringify(d)); });

print('\n============================================================');
print(' aggregations.js DONE.');
print('============================================================\n');
