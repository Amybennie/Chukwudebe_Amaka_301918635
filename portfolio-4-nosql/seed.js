// =============================================================================
// seed.js - Portfolio 4 (NoSQL / MongoDB)
// Student : Amaka Benedicta Chukwudebe
// Matric  : 2026/A/MIT/0517
// Course  : MIT 8103 Advanced Database Systems
// Cohort  : September 2026 (2026/2027 First Semester)
// Case    : CampusNest - Private Student Accommodation Booking
//
// Purpose
// -------
//   Generate and bulk-insert 42,000 maintenance ticket documents into the
//   `campusnest_nosql.maintenance_tickets` collection. The documents exercise
//   the four ticket categories (plumbing / electrical / furniture /
//   pest_control), each with its own polymorphic per-category fields.
//
//   The shape of every document matches the $jsonSchema validator created by
//   schema_validation.js (run that first).
//
// Run
// ---
//   mongosh mongodb://127.0.0.1:27017/campusnest_nosql seed.js
// =============================================================================
const db = db.getSiblingDB('campusnest_nosql');

print('\n============================================================');
print(' seed.js - generate 42,000+ maintenance ticket documents');
print('============================================================\n');

// ---------------------------------------------------------------------------
// 0. Idempotent - clear anything already in the collection. The schema
//    validator stays in place (deleteMany does not touch the validator).
// ---------------------------------------------------------------------------
print('[0] Deleting existing documents from maintenance_tickets ...');
const deleted = db.maintenance_tickets.deleteMany({});
print('    deletedCount = ' + deleted.deletedCount);

// ---------------------------------------------------------------------------
// 1. Reference data - real tenancies from PostgreSQL, plus technicians.
// ---------------------------------------------------------------------------
// Real reference data exported from PostgreSQL by run_p4.sh (pg_refs.json):
// every ticket is raised by a real tenant, in the real bed-space and lodge
// they rented, during the dates of their real tenancy. So the Mongo tickets
// line up with Portfolio 1's relational data.
const fs = require('fs');
const REFS_FILE = (typeof refsFile !== 'undefined') ? refsFile : 'pg_refs.json';
const refs = JSON.parse(fs.readFileSync(REFS_FILE, 'utf8'));
const tenancies = refs.tenancies;   // [{tenant_id, tenant_name, lodge_id, lodge_name, institution, room_code, start, end}]
print('    loaded ' + tenancies.length + ' real tenancies from ' + REFS_FILE +
      ' (' + refs.lodge_count + ' lodges)');

// Maintenance technicians employed by CampusNest (not tenants).
const technicians = [
    'Tunde Bakare', 'Ngozi Eze', 'Aisha Bello', 'Chidi Okafor', 'Bola Adeyemi',
    'Ibrahim Musa', 'Kunle Ogunleye', 'Emeka Nwosu', 'Fatima Sani', 'Seyi Adewale',
    'Obinna Igwe', 'Yusuf Abdullahi', 'Funke Ajayi', 'Chinwe Obi', 'Halima Idris',
    'Gbenga Olawale', 'Uche Okoro', 'Sani Garba', 'Tobi Fabunmi', 'Nkechi Onuoha',
    'Zainab Mohammed', 'Wale Adesanya'
];

// ---------------------------------------------------------------------------
// 2. Category weights. Plumbing and electrical are the most common
//    maintenance issues in student lodges (tap leaks, faulty sockets,
//    flickering lights). Furniture and pest control happen less often.
//    The weighted array below lets Math.random() pick a category.
// ---------------------------------------------------------------------------
const categoryWeights = [];
const categories = [
    { name: 'plumbing',     weight: 32 },
    { name: 'electrical',   weight: 28 },
    { name: 'furniture',    weight: 20 },
    { name: 'pest_control', weight: 20 }
];
categories.forEach(function (c) {
    for (let i = 0; i < c.weight; i++) categoryWeights.push(c.name);
});

// ---------------------------------------------------------------------------
// 3. Per-category reference data (the polymorphic fields).
// ---------------------------------------------------------------------------
const plumbingFixtures   = ['tap', 'shower', 'toilet', 'pipe'];
const electricalAppls    = ['socket', 'light', 'ac', 'fan', 'breaker'];
const furnitureItems     = ['bed', 'desk', 'chair', 'wardrobe', 'door'];
const furnitureDamage    = ['broken', 'loose', 'missing_part', 'stained'];
const pestTypes          = ['cockroach', 'rodent', 'bedbug', 'mosquito', 'termite'];
const pestLevels         = ['minor', 'moderate', 'severe'];
const pestTreatments     = ['spray', 'bait', 'fumigation', 'trap'];
const safetyHazards      = ['low', 'medium', 'high'];

// Per-category summary templates - realistic student-lodge complaints.
const summaryTemplates = {
    plumbing: [
        'Leaking tap in shared bathroom',
        'Blocked drain in kitchenette',
        'Running toilet in single room',
        'Burst pipe near shower',
        'Low water pressure in bathroom',
        'Water heater not heating',
        'Leaking shower head in ensuite',
        'Toilet not flushing properly'
    ],
    electrical: [
        'Wall socket sparking when charger plugged in',
        'Ceiling fan not working',
        'Light bulb flickering in bedroom',
        'Air conditioner not cooling',
        'Tripping breaker when iron used',
        'Light switch not responding',
        'Outdoor security light off',
        'Heater socket burned'
    ],
    furniture: [
        'Broken study desk leg',
        'Wardrobe door off hinge',
        'Broken bed slat',
        'Chair backrest loose',
        'Door handle broken',
        'Missing wardrobe shelf',
        'Bunk bed ladder unstable',
        'Window latch broken'
    ],
    pest_control: [
        'Cockroach infestation in kitchenette',
        'Rodent droppings in store room',
        'Bedbug bites reported',
        'Mosquito swarm in bedroom',
        'Termite damage on window frame',
        'Ants in food cabinet',
        'Lizard droppings in ceiling',
        'Spider webs across wardrobes'
    ]
};

const photoCaptions = [
    'Photo from tenant mobile app',
    'Close-up of affected area',
    'Wide shot of room',
    'Damage visible from this angle',
    'Photo taken after first visit'
];

const findingsOptions = [
    'Fault confirmed on arrival',
    'Minor wear, repairable',
    'Part requires replacement',
    'Referred to external vendor',
    'Issue not reproducible on visit',
    'Recurring fault, root cause identified'
];

const actionOptions = [
    'Repaired on site',
    'Part ordered, follow-up visit scheduled',
    'Temporary fix applied',
    'Vendor engaged for full treatment',
    'Adjusted and tested OK',
    'Logged for next maintenance cycle'
];

// Status-change note options (per status transition).
const noteOpenToInProgress = [
    'Ticket triaged and assigned to technician',
    'Technician dispatched',
    'Spare part availability confirmed'
];
const noteInProgressToResolved = [
    'Repair completed and tested',
    'Tenant confirmed fix',
    'Treatment applied, no recurrence observed'
];
const noteResolvedToClosed = [
    'Final inspection passed',
    'Tenant follow-up clear',
    'Ticket closed after observation window'
];

// ---------------------------------------------------------------------------
// 4. Helper functions.
// ---------------------------------------------------------------------------
function pick(arr)               { return arr[Math.floor(Math.random() * arr.length)]; }
function randInt(minIncl, maxIncl){ return Math.floor(Math.random() * (maxIncl - minIncl + 1)) + minIncl; }
function randBool(probTrue)      { return Math.random() < probTrue; }
function randDateDaysAgo(maxDays){ return new Date(Date.now() - Math.floor(Math.random() * maxDays) * 86400000); }
function offsetDate(baseMs, days){ return new Date(baseMs + days * 86400000); }

// Build the per-category polymorphic fields. Returns an object that is
// spread into the ticket document.
function categoryFields(category) {
    if (category === 'plumbing') {
        return {
            affected_fixture:        pick(plumbingFixtures),
            leak_present:            randBool(0.7),
            water_shut_off_needed:   randBool(0.25)
        };
    }
    if (category === 'electrical') {
        return {
            affected_appliance: pick(electricalAppls),
            voltage_issue:      randBool(0.35),
            spark_or_smoke:     randBool(0.20),
            safety_hazard:      pick(safetyHazards)
        };
    }
    if (category === 'furniture') {
        return {
            item_type:           pick(furnitureItems),
            damage_type:         pick(furnitureDamage),
            requires_replacement: randBool(0.4)
        };
    }
    // pest_control
    return {
        pest_type:          pick(pestTypes),
        infestation_level:  pick(pestLevels),
        treatment_method:   pick(pestTreatments)
    };
}

// Build status_history for a ticket given reported_at, status, resolved_at.
function buildStatusHistory(reportedAt, status, times, technicianName, reporter, lodgeId) {
    const manager = 'manager_lodge_' + lodgeId;
    const history = [{ status: 'open', changed_at: reportedAt, changed_by: reporter,
                       note: 'Ticket created via CampusNest mobile app' }];
    if (status === 'open') return history;
    history.push({ status: 'in_progress', changed_at: times.inProg, changed_by: manager,
                   note: pick(noteOpenToInProgress) });
    if (status === 'in_progress') return history;
    history.push({ status: 'resolved', changed_at: times.resolved, changed_by: technicianName,
                   note: pick(noteInProgressToResolved) });
    if (status === 'closed') {
        history.push({ status: 'closed', changed_at: times.closed, changed_by: manager,
                       note: pick(noteResolvedToClosed) });
    }
    return history;
}

// Build a small photo array (0..3 photos).
function buildPhotos(reportedAt) {
    const n = randInt(0, 3);
    const out = [];
    for (let i = 0; i < n; i++) {
        out.push({
            url:         'https://cdn.campusnest.ng/photos/' + Math.floor(Math.random() * 1e9) + '.jpg',
            uploaded_at: new Date(reportedAt.getTime() + randInt(1, 120) * 60000),
            caption:     pick(photoCaptions)
        });
    }
    return out;
}

// Build technician visits. 0 for open/in_progress tickets; 1..2 for
// resolved/closed tickets.
function buildVisits(times, status, technicianName) {
    if (status === 'open' || status === 'in_progress') return [];
    const n = randInt(1, 2);
    const out = [];
    const span = times.resolved.getTime() - times.inProg.getTime();
    for (let i = 0; i < n; i++) {
        out.push({
            visit_id:        NumberInt(i + 1),
            technician_name: technicianName,
            // visits happen between work starting and the fix (last visit = fix)
            visited_at:      new Date(times.inProg.getTime() + span * (i + 1) / n),
            findings:        pick(findingsOptions),
            action_taken:    pick(actionOptions)
        });
    }
    return out;
}

// ---------------------------------------------------------------------------
// 5. Main generation loop. Target: 42,000 documents.
//    We batch insertMany in chunks of 1000 and print progress every 5000.
// ---------------------------------------------------------------------------
const TARGET = 42000;
const BATCH  = 1000;

print('\n[5] Generating ' + TARGET + ' maintenance ticket documents in batches of ' + BATCH + ' ...');

let batch = [];
let insertedTotal = 0;
let generatedTotal = 0;

// ticket_id starts after the four valid example docs that schema_validation.js
// already inserted (ticket_id 1..4). We start at 5 to avoid collision.
let nextTicketId = 5;

const NOW_MS = Date.now();
for (let i = 0; i < TARGET; i++) {
    const t = tenancies[randInt(0, tenancies.length - 1)];
    const lg = { lodge_id: t.lodge_id, lodge_name: t.lodge_name };
    const chosenRoom = { room_code: t.room_code };
    const tenant = { tenant_id: t.tenant_id };
    const category = pick(categoryWeights);

    // reported_at: a random moment inside this tenant's tenancy, never in the future.
    const tStart = new Date(t.start + 'T07:00:00Z').getTime();
    const tEnd   = Math.min(new Date(t.end + 'T07:00:00Z').getTime(), NOW_MS - 3600000);
    const reportedAt = new Date(tStart + Math.random() * Math.max(tEnd - tStart, 3600000));

    // Old tickets are almost all resolved; tickets from the last few weeks
    // are more likely still open.
    // One consistent timeline: reported -> in_progress -> resolved -> closed.
    // How long a fix takes depends on the category. Status is whatever that
    // timeline has reached by now, so nothing is dated in the future.
    const DAY = 86400000;
    const FIX = { plumbing: [0.5, 5], electrical: [0.5, 4], furniture: [2, 12], pest_control: [3, 14] }[category];
    const inProgMs   = reportedAt.getTime() + (0.1 + Math.random() * 1.9) * DAY;
    const resolvedMs = inProgMs + (FIX[0] + Math.random() * (FIX[1] - FIX[0])) * DAY;
    const closedMs   = resolvedMs + (1 + Math.random() * 6) * DAY;
    let status, resolvedAt = null;
    if (closedMs <= NOW_MS && Math.random() < 0.65) status = 'closed';
    else if (resolvedMs <= NOW_MS) status = 'resolved';
    else if (inProgMs <= NOW_MS)   status = 'in_progress';
    else                           status = 'open';
    if (status === 'resolved' || status === 'closed') resolvedAt = new Date(resolvedMs);
    const times = { inProg: new Date(inProgMs), resolved: resolvedAt, closed: new Date(closedMs) };

    // 5% of tickets are logged by the lodge manager, not a tenant.
    const tenantId = (Math.random() < 0.05) ? null : NumberInt(tenant.tenant_id);
    const reporter = tenantId === null ? 'manager_lodge_' + lg.lodge_id : 'tenant_' + tenant.tenant_id;

    const technicianName = pick(technicians);

    const doc = {
        ticket_id:        NumberInt(nextTicketId++),
        lodge_id:         NumberInt(lg.lodge_id),
        lodge_name:       lg.lodge_name,
        room_code:        chosenRoom.room_code,
        tenant_id:        tenantId,
        category:         category,
        reported_at:      reportedAt,
        status:           status,
        summary:          pick(summaryTemplates[category]),
        status_history:   buildStatusHistory(reportedAt, status, times, technicianName, reporter, lg.lodge_id),
        photos:           buildPhotos(reportedAt),
        technician_visits: buildVisits(times, status, technicianName)
    };

    // Polymorphic per-category fields - spread in.
    const extra = categoryFields(category);
    Object.keys(extra).forEach(function (k) { doc[k] = extra[k]; });

    if (resolvedAt !== null) doc.resolved_at = resolvedAt;

    batch.push(doc);
    generatedTotal++;

    // flush batch
    if (batch.length === BATCH) {
        const res = db.maintenance_tickets.insertMany(batch, { ordered: false });
        insertedTotal += Object.keys(res.insertedIds).length;
        batch = [];

        if (generatedTotal % 5000 === 0) {
            print('   progress: generated=' + generatedTotal + ' insertedTotal=' + insertedTotal);
        }
    }
}

// flush any remainder
if (batch.length > 0) {
    const res = db.maintenance_tickets.insertMany(batch, { ordered: false });
    insertedTotal += Object.keys(res.insertedIds).length;
}

print('\n[6] Generation complete.');
print('    Target           = ' + TARGET);
print('    Generated        = ' + generatedTotal);
print('    Inserted (ack)   = ' + insertedTotal);

// ---------------------------------------------------------------------------
// 7. Final count - must be >= 40,000 (the four example docs from
//    schema_validation.js plus the generated bulk).
// ---------------------------------------------------------------------------
const finalCount = db.maintenance_tickets.estimatedDocumentCount();
print('\n[7] db.maintenance_tickets.estimatedDocumentCount() = ' + finalCount);
if (finalCount < 40000) {
    print('    *** WARNING: final count is below the 40,000 target. ***');
} else {
    print('    OK - final count meets the 40,000+ target.');
}

// ---------------------------------------------------------------------------
// 8. Quick sanity print - per-category counts so the student can verify the
//    weighted distribution looks sensible.
// ---------------------------------------------------------------------------
print('\n[8] Per-category counts (sanity check):');
const catCounts = db.maintenance_tickets.aggregate([
    { $group: { _id: '$category', count: { $sum: 1 } } },
    { $sort:  { count: -1 } }
]).toArray();
catCounts.forEach(function (d) { print('  ' + JSON.stringify(d)); });

print('\n============================================================');
print(' seed.js DONE.');
print('============================================================\n');
