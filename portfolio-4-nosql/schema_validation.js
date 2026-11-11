// =============================================================================
// schema_validation.js - Portfolio 4 (NoSQL / MongoDB)
// Student : Amaka Benedicta Chukwudebe
// Matric  : 2026/A/MIT/0517
// Course  : MIT 8103 Advanced Database Systems
// Cohort  : September 2026 (2026/2027 First Semester)
// Case    : CampusNest - Private Student Accommodation Booking
//
// Purpose
// -------
//   Create the `maintenance_tickets` collection inside the `campusnest_nosql`
//   database with a $jsonSchema validator. The validator enforces the fields
//   that EVERY maintenance ticket must have (the common envelope), while
//   leaving additionalProperties:true so that each ticket category can carry
//   its own polymorphic fields (plumbing vs electrical vs furniture vs
//   pest_control). That is exactly the workload MongoDB was designed for and
//   that a single SQL table with dozens of NULL columns cannot model cleanly.
//
// Run
// ---
//   mongosh mongodb://127.0.0.1:27017/campusnest_nosql schema_validation.js
// =============================================================================
const db = db.getSiblingDB('campusnest_nosql');

print('\n============================================================');
print(' schema_validation.js - create maintenance_tickets with');
print(' a $jsonSchema validator (polymorphic per-category fields)');
print('============================================================\n');

// ---------------------------------------------------------------------------
// 1. Fresh start - drop the collection if it already exists from a prior run.
//    We also drop any indexes (drop() takes care of that automatically).
// ---------------------------------------------------------------------------
if (db.maintenance_tickets.exists() !== null) {
    print('[1] Dropping existing maintenance_tickets collection ...');
    db.maintenance_tickets.drop();
} else {
    print('[1] maintenance_tickets does not exist yet - nothing to drop.');
}

// ---------------------------------------------------------------------------
// 2. The JSON schema validator.
//
//    bsonType 'int' = 32-bit int (matches what seed.js inserts).
//    bsonType 'date' = ISODate in MongoDB.
//    'enum' inside 'properties' uses the JSON-Schema 'enum' keyword, which
//    MongoDB's $jsonSchema supports.
//
//    additionalProperties:true is deliberate: plumbing tickets add
//    {affected_fixture, leak_present, water_shut_off_needed}, electrical
//    tickets add {affected_appliance, voltage_issue, spark_or_smoke,
//    safety_hazard}, furniture adds {item_type, damage_type,
//    requires_replacement}, and pest_control adds {pest_type,
//    infestation_level, treatment_method}. We document the per-category
//    extras in README.md and rely on the seed to populate them correctly.
// ---------------------------------------------------------------------------
const validator = {
    $jsonSchema: {
        bsonType: 'object',
        required: [
            'ticket_id',
            'lodge_id',
            'lodge_name',
            'room_code',
            'category',
            'reported_at',
            'status',
            'summary',
            'status_history',
            'photos',
            'technician_visits'
        ],
        properties: {
            ticket_id:        { bsonType: 'int', description: 'sequential ticket id, must be int' },
            lodge_id:         { bsonType: 'int', description: '1..4 - must be int' },
            lodge_name:       { bsonType: 'string', description: 'human-readable lodge name' },
            room_code:        { bsonType: 'string', description: 'e.g. AH-S-101' },
            // tenant_id is intentionally NOT in 'required' - some tickets are
            // logged by lodge managers before a tenant is identified, so it is
            // nullable. When present, it must be an int or null. We use the
            // array form of bsonType so the validator accepts both NumberInt
            // writes and explicit null writes from seed.js (which writes null
            // for ~5% of tickets).
            tenant_id:        { bsonType: ['int', 'null'], description: 'optional tenant id, nullable' },
            category:         { enum: ['plumbing', 'electrical', 'furniture', 'pest_control'] },
            reported_at:      { bsonType: 'date' },
            // resolved_at is optional (open/in_progress tickets have none).
            resolved_at:      { bsonType: 'date' },
            status:           { enum: ['open', 'in_progress', 'resolved', 'closed'] },
            summary:          { bsonType: 'string' },
            status_history: {
                bsonType: 'array',
                items: {
                    bsonType: 'object',
                    required: ['status', 'changed_at', 'changed_by', 'note'],
                    properties: {
                        status:     { enum: ['open', 'in_progress', 'resolved', 'closed'] },
                        changed_at: { bsonType: 'date' },
                        changed_by: { bsonType: 'string' },
                        note:       { bsonType: 'string' }
                    }
                }
            },
            photos: {
                bsonType: 'array',
                items: {
                    bsonType: 'object',
                    required: ['url', 'uploaded_at', 'caption'],
                    properties: {
                        url:         { bsonType: 'string' },
                        uploaded_at: { bsonType: 'date' },
                        caption:     { bsonType: 'string' }
                    }
                }
            },
            technician_visits: {
                bsonType: 'array',
                items: {
                    bsonType: 'object',
                    required: ['visit_id', 'technician_name', 'visited_at', 'findings', 'action_taken'],
                    properties: {
                        visit_id:        { bsonType: 'int' },
                        technician_name: { bsonType: 'string' },
                        visited_at:      { bsonType: 'date' },
                        findings:        { bsonType: 'string' },
                        action_taken:    { bsonType: 'string' }
                    }
                }
            }
        },
        additionalProperties: true
    }
};

// ---------------------------------------------------------------------------
// 3. Create the collection with the validator and an explicit validationLevel
//    of 'strict' (the default) and validationAction 'error' (the default) -
//    i.e. writes that fail validation are rejected, not just logged.
// ---------------------------------------------------------------------------
print('[2] Creating maintenance_tickets with $jsonSchema validator ...');
db.createCollection('maintenance_tickets', {
    validator: validator,
    validationLevel: 'strict',
    validationAction: 'error'
});

// Show the validator so the student can screenshot the collection info.
const collInfo = db.runCommand({ listCollections: 1, filter: { name: 'maintenance_tickets' } });
print('\n[3] Validator now on the collection (from db.getCollectionInfos):');
const opts = ((collInfo.cursor.firstBatch || [])[0] || {}).options || {};
const js = (opts.validator || {}).$jsonSchema || {};
print('    validationLevel  = ' + opts.validationLevel + ', validationAction = ' + opts.validationAction);
print('    required fields  = ' + JSON.stringify(js.required));
print('    category enum    = ' + JSON.stringify(((js.properties || {}).category || {}).enum));
print('    status enum      = ' + JSON.stringify(((js.properties || {}).status || {}).enum));

// ---------------------------------------------------------------------------
// 4. Insert one VALID example document per category (4 documents total).
//    Each example shows the per-category polymorphic fields the validator
//    accepts thanks to additionalProperties:true.
// ---------------------------------------------------------------------------
print('\n[4] Inserting four VALID example documents (one per category) ...');

const now = new Date();

const validPlumbing = {
    ticket_id: NumberInt(1),
    lodge_id: NumberInt(1),
    lodge_name: 'Akoka Heights Lodge',
    room_code: 'AH-S-101',
    tenant_id: NumberInt(1001),
    category: 'plumbing',
    reported_at: new Date(now.getTime() - 3 * 86400000),
    status: 'in_progress',
    summary: 'Leaking tap in shared bathroom',
    status_history: [
        { status: 'open',        changed_at: new Date(now.getTime() - 3 * 86400000), changed_by: 'tenant_1001', note: 'Ticket created via mobile app' },
        { status: 'in_progress', changed_at: new Date(now.getTime() - 2 * 86400000), changed_by: 'manager_ah',   note: 'Plumber Tunde Bakare dispatched' }
    ],
    photos: [
        { url: 'https://cdn.campusnest.ng/photos/plumbing_1.jpg', uploaded_at: new Date(now.getTime() - 3 * 86400000), caption: 'Tap dripping continuously' }
    ],
    technician_visits: [
        { visit_id: NumberInt(1), technician_name: 'Tunde Bakare', visited_at: new Date(now.getTime() - 2 * 86400000), findings: 'Worn washer', action_taken: 'Replaced washer, tap tested OK' }
    ],
    // plumbing-specific polymorphic fields
    affected_fixture: 'tap',
    leak_present: true,
    water_shut_off_needed: false
};

const validElectrical = {
    ticket_id: NumberInt(2),
    lodge_id: NumberInt(2),
    lodge_name: 'Yaba Tech Suites',
    room_code: 'YT-S2-201',
    tenant_id: NumberInt(1002),
    category: 'electrical',
    reported_at: new Date(now.getTime() - 5 * 86400000),
    status: 'resolved',
    resolved_at: new Date(now.getTime() - 1 * 86400000),
    summary: 'Wall socket sparking when laptop charger plugged in',
    status_history: [
        { status: 'open',        changed_at: new Date(now.getTime() - 5 * 86400000), changed_by: 'tenant_1002', note: 'Spark reported' },
        { status: 'in_progress', changed_at: new Date(now.getTime() - 4 * 86400000), changed_by: 'manager_yt',   note: 'Electrician dispatched' },
        { status: 'resolved',    changed_at: new Date(now.getTime() - 1 * 86400000), changed_by: 'Aisha Bello',  note: 'Socket replaced and load tested' }
    ],
    photos: [
        { url: 'https://cdn.campusnest.ng/photos/elec_2a.jpg', uploaded_at: new Date(now.getTime() - 5 * 86400000), caption: 'Burn mark around socket pins' }
    ],
    technician_visits: [
        { visit_id: NumberInt(1), technician_name: 'Aisha Bello', visited_at: new Date(now.getTime() - 4 * 86400000), findings: 'Loose live wire', action_taken: 'Re-terminated wiring and replaced face plate' }
    ],
    // electrical-specific polymorphic fields
    affected_appliance: 'socket',
    voltage_issue: true,
    spark_or_smoke: true,
    safety_hazard: 'high'
};

const validFurniture = {
    ticket_id: NumberInt(3),
    lodge_id: NumberInt(3),
    lodge_name: 'Ojo Gardens Residence',
    room_code: 'OG-S4-301',
    tenant_id: NumberInt(1003),
    category: 'furniture',
    reported_at: new Date(now.getTime() - 10 * 86400000),
    status: 'open',
    summary: 'Broken study desk leg in shared 4-person room',
    status_history: [
        { status: 'open', changed_at: new Date(now.getTime() - 10 * 86400000), changed_by: 'tenant_1003', note: 'Desk wobbles badly, leg snapped' }
    ],
    photos: [
        { url: 'https://cdn.campusnest.ng/photos/furn_3a.jpg', uploaded_at: new Date(now.getTime() - 10 * 86400000), caption: 'Snapped leg on study desk' }
    ],
    technician_visits: [],
    // furniture-specific polymorphic fields
    item_type: 'desk',
    damage_type: 'broken',
    requires_replacement: true
};

const validPestControl = {
    ticket_id: NumberInt(4),
    lodge_id: NumberInt(4),
    lodge_name: 'Nsukka Scholars Lodge',
    room_code: 'NS-S-101',
    tenant_id: NumberInt(1004),
    category: 'pest_control',
    reported_at: new Date(now.getTime() - 7 * 86400000),
    status: 'closed',
    resolved_at: new Date(now.getTime() - 2 * 86400000),
    summary: 'Cockroach infestation in kitchenette',
    status_history: [
        { status: 'open',        changed_at: new Date(now.getTime() - 7 * 86400000), changed_by: 'tenant_1004', note: 'Cockroaches seen at night' },
        { status: 'in_progress', changed_at: new Date(now.getTime() - 6 * 86400000), changed_by: 'manager_ns',   note: 'Pest control vendor booked' },
        { status: 'resolved',    changed_at: new Date(now.getTime() - 3 * 86400000), changed_by: 'Ngozi Eze',    note: 'Spray completed, no sightings for 24h' },
        { status: 'closed',      changed_at: new Date(now.getTime() - 2 * 86400000), changed_by: 'manager_ns',   note: 'Follow-up clear, ticket closed' }
    ],
    photos: [
        { url: 'https://cdn.campusnest.ng/photos/pest_4a.jpg', uploaded_at: new Date(now.getTime() - 7 * 86400000), caption: 'Cockroaches under sink' },
        { url: 'https://cdn.campusnest.ng/photos/pest_4b.jpg', uploaded_at: new Date(now.getTime() - 6 * 86400000), caption: 'Kitchenette corners treated' }
    ],
    technician_visits: [
        { visit_id: NumberInt(1), technician_name: 'Ngozi Eze', visited_at: new Date(now.getTime() - 6 * 86400000), findings: 'Active infestation under sink and behind fridge', action_taken: 'Residual spray + bait stations installed' }
    ],
    // pest_control-specific polymorphic fields
    pest_type: 'cockroach',
    infestation_level: 'moderate',
    treatment_method: 'spray'
};

const validDocs = [validPlumbing, validElectrical, validFurniture, validPestControl];
const validResult = db.maintenance_tickets.insertMany(validDocs, { ordered: true });
print('   Inserted ' + Object.keys(validResult.insertedIds).length + ' valid example documents:');
print('   - plumbing (ticket_id=1, Akoka Heights Lodge)');
print('   - electrical (ticket_id=2, Yaba Tech Suites)');
print('   - furniture (ticket_id=3, Ojo Gardens Residence)');
print('   - pest_control (ticket_id=4, Nsukka Scholars Lodge)');

// ---------------------------------------------------------------------------
// 5. Attempt to insert ONE INVALID document - missing the required `category`
//    field. The validator must reject it. We wrap the call in try/catch and
//    print the error so the student can screenshot the rejection.
// ---------------------------------------------------------------------------
print('\n[5] Attempting to insert an INVALID document (missing required `category`) ...');
const invalidDoc = {
    ticket_id: NumberInt(999),
    lodge_id: NumberInt(1),
    lodge_name: 'Akoka Heights Lodge',
    room_code: 'AH-S2-201',
    // category: deliberately omitted - should fail validation
    reported_at: new Date(),
    status: 'open',
    summary: 'This document should be rejected by the validator',
    status_history: [],
    photos: [],
    technician_visits: []
};

try {
    db.maintenance_tickets.insertOne(invalidDoc);
    // If we reach here, validation did NOT fire - that is a bug.
    print('   *** UNEXPECTED: invalid document was accepted! Validator not enforced. ***');
} catch (err) {
    print('   *** EXPECTED REJECTION ***');
    print('   Error name    : ' + err.name);
    print('   Error code    : ' + err.code);
    print('   Error message : ' + err.errmsg);
}

// ---------------------------------------------------------------------------
// 6. Final state - count and a sample document per category for the README.
// ---------------------------------------------------------------------------
print('\n[6] Final state of maintenance_tickets:');
print('   estimatedDocumentCount = ' + db.maintenance_tickets.estimatedDocumentCount());
print('\n   One example document per category (category, status, the category-specific fields):');
const categories = ['plumbing', 'electrical', 'furniture', 'pest_control'];
categories.forEach(function (cat) {
    print('\n   --- category: ' + cat + ' ---');
    const doc = db.maintenance_tickets.findOne({ category: cat }, { _id: 0, status_history: 0, photos: 0, technician_visits: 0 });
    print('   ' + JSON.stringify(doc));
});

print('\n============================================================');
print(' schema_validation.js DONE.');
print('============================================================\n');
