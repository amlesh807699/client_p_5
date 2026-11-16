# Database Schema Specification
## Class Waitlist SMS Notification Job (Twilio Mock)
**Ticket ID:** ENG-135180  
**Epic:** Core Infrastructure Overhaul  
**Database Engine:** MySQL 8.0+ (InnoDB Engine, Strict SQL Mode)  
**Encoding:** `utf8mb4` / `utf8mb4_unicode_ci`  
**Schema Artifact:** [`database/schema.sql`](file:///c:/Users/amles/Desktop/tw/database/schema.sql)  

---

## 1. Schema Overview & Relational Architecture

The relational schema is engineered to Third Normal Form (3NF) and Boyce-Codd Normal Form (BCNF) standards to replace manual records and spreadsheets with an ACID-compliant transactional data architecture.

### 1.1 Core Entities & Architectural Boundaries
The architecture is structured around seven relational entities:
1. **`students`**: Master directory of students eligible for course registration and waitlists, enforcing international E.164 phone standards.
2. **`classes`**: Academic sections defining physical seating capacity, operational status, schedule, and offer reservation timeouts.
3. **`class_enrollments`**: Active and historical student registrations, utilizing stored virtual tokens to enforce a single active enrollment per student per course.
4. **`seat_release_events`**: Immutable audit ledger recording every formal seat vacancy event (drops, capacity increases, or offer timeouts).
5. **`waitlist_entries`**: Strict FIFO queues maintaining integer ordinal positions for `WAITING` candidates and tracking time-bound reservation states (`OFFERED`, `CONVERTED`, `EXPIRED`, `WITHDRAWN`).
6. **`sms_notifications`**: Complete dispatch audit trail for simulated Twilio SMS notifications, enforcing idempotency and preventing duplicate alerts.
7. **`system_audit_logs`**: General security, administrative action, and telemetry log scrubbed of sensitive PII.

---

## 2. Comprehensive Data Dictionary

### 2.1 Table: `students`
Master student identity directory.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Internal synthetic surrogate primary key. |
| `student_uuid` | `CHAR(36)` | `NOT NULL`, `UNIQUE` | — | Public external UUID v4 identifier. |
| `first_name` | `VARCHAR(100)` | `NOT NULL` | — | Student legal first name. |
| `last_name` | `VARCHAR(100)` | `NOT NULL` | — | Student legal surname / family name. |
| `email` | `VARCHAR(255)` | `NOT NULL`, `UNIQUE` | — | Institutional academic email address. |
| `phone` | `VARCHAR(20)` | `NOT NULL`, `CHECK` (E.164 format) | — | Destination phone for SMS notifications. |
| `status` | `ENUM('ACTIVE', 'SUSPENDED', 'ARCHIVED')` | `NOT NULL` | `'ACTIVE'` | Operational account status. |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Record creation timestamp (millisecond precision). |
| `updated_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Automatic record mutation timestamp. |
| `deleted_at` | `DATETIME(3)` | `NULL` | `NULL` | Soft deletion timestamp for GDPR/audit retention. |

**Table Constraints & Indexes:**
- `CONSTRAINT uq_students_uuid UNIQUE (student_uuid)`
- `CONSTRAINT uq_students_email UNIQUE (email)`
- `CONSTRAINT chk_students_phone_e164 CHECK (phone REGEXP '^\\+[1-9][0-9]{1,14}$')`
- `INDEX idx_students_phone (phone)`: Fast lookups during simulated webhook callbacks.
- `INDEX idx_students_status (status)`: Filter for active students.
- `INDEX idx_students_name (last_name, first_name)`: Staff directory searches.

---

### 2.2 Table: `classes`
Course catalog sections and seating limits.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Internal synthetic primary key. |
| `class_code` | `VARCHAR(30)` | `NOT NULL`, `UNIQUE` | — | Academic catalog course code (e.g., `CS-101`). |
| `title` | `VARCHAR(200)` | `NOT NULL` | — | Full course title. |
| `description` | `TEXT` | `NULL` | `NULL` | Course syllabus and prerequisite overview. |
| `instructor` | `VARCHAR(150)` | `NOT NULL` | — | Assigned faculty or instructor name. |
| `classroom` | `VARCHAR(100)` | `NOT NULL` | — | Physical building and room assignment. |
| `start_date` | `DATE` | `NOT NULL` | — | Term start date. |
| `end_date` | `DATE` | `NOT NULL`, `CHECK` | — | Term end date (`end_date >= start_date`). |
| `start_time` | `TIME` | `NOT NULL` | — | Daily session start time. |
| `end_time` | `TIME` | `NOT NULL` | — | Daily session conclusion time. |
| `max_capacity` | `INT UNSIGNED` | `NOT NULL`, `CHECK (> 0)` | — | Hard ceiling of physical classroom seats. |
| `max_waitlist_capacity` | `INT UNSIGNED` | `NULL` | `NULL` | Optional waitlist cap (`NULL` = unbounded). |
| `status` | `ENUM('DRAFT', 'OPEN', 'FULL', 'CANCELLED', 'COMPLETED')` | `NOT NULL` | `'OPEN'` | Operational lifecycle status of the course section. |
| `offer_timeout_hours` | `INT UNSIGNED` | `NOT NULL` | `24` | Duration granted to waitlisted student to accept offer. |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Record creation timestamp. |
| `updated_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Auto-updating timestamp. |
| `deleted_at` | `DATETIME(3)` | `NULL` | `NULL` | Soft deletion timestamp. |

**Table Constraints & Indexes:**
- `CONSTRAINT uq_classes_code UNIQUE (class_code)`
- `CONSTRAINT chk_classes_capacity CHECK (max_capacity > 0)`
- `CONSTRAINT chk_classes_dates CHECK (end_date >= start_date)`
- `INDEX idx_classes_status_dates (status, start_date)`: Fast catalog filtering.
- `INDEX idx_classes_instructor (instructor)`: Instructor workload queries.

---

### 2.3 Table: `class_enrollments`
Official student enrollments.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Primary key. |
| `class_id` | `BIGINT UNSIGNED` | `NOT NULL`, `FK` (`classes.id`) | — | Enrolled class section. |
| `student_id` | `BIGINT UNSIGNED` | `NOT NULL`, `FK` (`students.id`) | — | Enrolled student. |
| `status` | `ENUM('ENROLLED', 'DROPPED', 'CANCELLED')` | `NOT NULL` | `'ENROLLED'` | Enrollment status. |
| `enrolled_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Official enrollment timestamp. |
| `dropped_at` | `DATETIME(3)` | `NULL` | `NULL` | Cancellation timestamp. |
| `drop_reason` | `VARCHAR(255)` | `NULL` | `NULL` | Administrative cancellation reason. |
| `active_enrollment_token` | `VARCHAR(20)` | `STORED GENERATED` | — | Token for unique active enrollment enforcement. |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Audit creation timestamp. |
| `updated_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Auto-updating timestamp. |

**Generated Token & Unique Constraint:**
```sql
active_enrollment_token VARCHAR(20) GENERATED ALWAYS AS (
    CASE WHEN status = 'ENROLLED' THEN 'ENROLLED' ELSE NULL END
) STORED;
CONSTRAINT uq_active_enrollment UNIQUE (class_id, student_id, active_enrollment_token);
```
*Rationale:* In MySQL, multiple `NULL` values are permitted in a `UNIQUE` index. When a student drops, the token becomes `NULL`, allowing the student to potentially re-enroll later without violating historical uniqueness, while strictly preventing two simultaneous `ENROLLED` records.

---

### 2.4 Table: `seat_release_events`
Immutable seat release ledger.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Primary key. |
| `event_uuid` | `CHAR(36)` | `NOT NULL`, `UNIQUE` | — | External UUID for tracing. |
| `class_id` | `BIGINT UNSIGNED` | `NOT NULL`, `FK` (`classes.id`) | — | Class with released seats. |
| `triggered_by` | `VARCHAR(100)` | `NOT NULL` | — | Username or `SYSTEM_WORKER`. |
| `reason` | `ENUM('ENROLLMENT_DROPPED', 'CAPACITY_EXPANDED', 'OFFER_EXPIRED', 'MANUAL_RELEASE')` | `NOT NULL` | — | Cause of seat vacancy. |
| `seats_released` | `INT UNSIGNED` | `NOT NULL`, `CHECK (> 0)` | `1` | Count of seats made available. |
| `notes` | `TEXT` | `NULL` | `NULL` | Administrative notes. |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Creation timestamp. |

**Table Constraints & Indexes:**
- `CONSTRAINT uq_seat_release_uuid UNIQUE (event_uuid)`
- `CONSTRAINT chk_release_seats CHECK (seats_released > 0)`
- `INDEX idx_seat_release_class_created (class_id, created_at)`

---

### 2.5 Table: `waitlist_entries`
Ordered waitlist queues and reservation states.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Primary key. |
| `class_id` | `BIGINT UNSIGNED` | `NOT NULL`, `FK` (`classes.id`) | — | Class section. |
| `student_id` | `BIGINT UNSIGNED` | `NOT NULL`, `FK` (`students.id`) | — | Waitlisted student. |
| `position` | `INT UNSIGNED` | `NULL`, `CHECK (> 0)` | — | Ordinal position `[1..N]` when `WAITING`; `NULL` when offered or concluded. |
| `status` | `ENUM('WAITING', 'OFFERED', 'CONVERTED', 'EXPIRED', 'WITHDRAWN', 'CANCELLED')` | `NOT NULL` | `'WAITING'` | State of waitlist entry. |
| `offered_at` | `DATETIME(3)` | `NULL` | `NULL` | Timestamp when notification offer was dispatched. |
| `offer_expires_at` | `DATETIME(3)` | `NULL` | `NULL` | Expiration deadline for offer. |
| `converted_at` | `DATETIME(3)` | `NULL` | `NULL` | Timestamp when student confirmed and converted. |
| `withdrawn_at` | `DATETIME(3)` | `NULL` | `NULL` | Voluntary withdrawal timestamp. |
| `active_waitlist_token` | `VARCHAR(20)` | `STORED GENERATED` | — | Token for unique active waitlist entry enforcement. |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Queue entry timestamp. |
| `updated_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Auto-updating timestamp. |

**Generated Token & Unique Queue Constraints:**
```sql
active_waitlist_token VARCHAR(20) GENERATED ALWAYS AS (
    CASE WHEN status IN ('WAITING', 'OFFERED') THEN 'ACTIVE' ELSE NULL END
) STORED;
CONSTRAINT uq_class_position UNIQUE (class_id, position);
CONSTRAINT uq_active_waitlist_entry UNIQUE (class_id, student_id, active_waitlist_token);
```
*Rationale:*
1. `uq_class_position`: Guarantees that no two students can occupy the same ordinal rank in a class. When a student is offered a seat, their position is set to `NULL`, freeing that rank.
2. `uq_active_waitlist_entry`: Guarantees that a student cannot be placed on the waitlist twice for the same class while actively waiting or holding an offer.

---

### 2.6 Table: `sms_notifications`
Simulated Twilio SMS audit records and retry ledger.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Primary key. |
| `notification_uuid` | `CHAR(36)` | `NOT NULL`, `UNIQUE` | — | Public external UUID. |
| `waitlist_entry_id` | `BIGINT UNSIGNED` | `NOT NULL`, `FK` (`waitlist_entries.id`) | — | Target waitlist entry. |
| `seat_release_event_id` | `BIGINT UNSIGNED` | `NULL`, `FK` (`seat_release_events.id`) | `NULL` | Originating release event. |
| `recipient_phone` | `VARCHAR(20)` | `NOT NULL` | — | Recipient phone number (E.164). |
| `message_body` | `VARCHAR(500)` | `NOT NULL` | — | Exact text dispatched to carrier simulation. |
| `idempotency_key` | `VARCHAR(128)` | `NOT NULL`, `UNIQUE` | — | Cryptographic hash preventing double-sends. |
| `status` | `ENUM('PENDING', 'SENT', 'FAILED')` | `NOT NULL` | `'PENDING'` | Dispatch delivery outcome. |
| `attempt_number` | `TINYINT UNSIGNED` | `NOT NULL`, `CHECK (1..5)` | `1` | Sequential attempt counter. |
| `mock_message_sid` | `VARCHAR(64)` | `NULL` | `NULL` | Simulated Twilio SID (e.g. `SM...`). |
| `error_code` | `VARCHAR(32)` | `NULL` | `NULL` | Mock simulated error code (e.g. `21211`). |
| `error_message` | `VARCHAR(255)` | `NULL` | `NULL` | Diagnostic failure message. |
| `sent_at` | `DATETIME(3)` | `NULL` | `NULL` | Timestamp of successful transmission. |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Initial creation timestamp. |
| `updated_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Auto-updating timestamp. |

**Constraints & Performance Indexes:**
- `CONSTRAINT uq_notification_uuid UNIQUE (notification_uuid)`
- `CONSTRAINT uq_idempotency_key UNIQUE (idempotency_key)`
- `CONSTRAINT uq_entry_attempt UNIQUE (waitlist_entry_id, attempt_number)`
- `INDEX idx_notifications_waitlist_status (waitlist_entry_id, status)`
- `INDEX idx_notifications_status_created (status, created_at)`

---

### 2.7 Table: `system_audit_logs`
Enterprise security, operation, and telemetry ledger.

| Column | Data Type | Constraints | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `BIGINT UNSIGNED` | `PRIMARY KEY`, `AUTO_INCREMENT` | — | Primary key. |
| `event_name` | `VARCHAR(100)` | `NOT NULL` | — | Telemetry name: `[Analytics] User interacted with...` |
| `entity_type` | `VARCHAR(50)` | `NOT NULL` | — | Domain entity type (`CLASS`, `WAITLIST`, etc.). |
| `entity_id` | `BIGINT UNSIGNED` | `NOT NULL` | — | Foreign surrogate identifier. |
| `performed_by` | `VARCHAR(100)` | `NOT NULL` | — | Staff username or `SYSTEM`. |
| `payload_summary` | `JSON` | `NULL` | `NULL` | Scrubbed contextual metadata (zero PII). |
| `created_at` | `DATETIME(3)` | `NOT NULL` | `CURRENT_TIMESTAMP(3)` | Event timestamp. |

---

## 3. Concurrency, Locking & Transaction Strategies

### 3.1 Race Condition: Concurrent Seat Releases
When two staff members attempt to release seats or drop students at the exact same millisecond:
1. The transaction acquires an exclusive row lock on the class record:
   ```sql
   SELECT id, max_capacity FROM classes WHERE id = :classId FOR UPDATE;
   ```
2. The transaction selects the head of the waitlist with a row lock:
   ```sql
   SELECT id, student_id, position 
   FROM waitlist_entries 
   WHERE class_id = :classId AND status = 'WAITING' 
   ORDER BY position ASC 
   LIMIT 1 
   FOR UPDATE;
   ```
3. Because InnoDB executes row-level locking on indexed ranges, the concurrent transaction is forced to wait until the first commits. The second transaction then sees the updated queue state (`position = 1` is now the subsequent student), preventing race conditions or double allocations.

### 3.2 Dynamic Queue Re-Indexing Strategy
When a student in position $K$ leaves the queue:
```sql
UPDATE waitlist_entries
SET position = position - 1
WHERE class_id = :classId 
  AND status = 'WAITING' 
  AND position > :vacatedPosition;
```
This is executed inside the same atomic transaction, ensuring contiguity: $[1, 2, 3, \dots, N]$.

### 3.3 Idempotency Key Generation
The `idempotency_key` is derived deterministically:
$$\text{idempotency\_key} = \text{SHA-256}(\text{"OFFER-"} \parallel \text{waitlist\_entry\_id} \parallel \text{"-"} \parallel \text{seat\_release\_event\_id} \parallel \text{"-ATTEMPT-"} \parallel \text{attempt\_number})$$
If a client or proxy double-submits the dispatch request, MySQL catches the duplicate key violation on `uq_idempotency_key`, allowing the API layer to return the original notification record safely.

---

## 4. Query Performance & Indexing Analysis

| Query Pattern | Predicates / Joins | Serving Index | Expected Cost & Plan |
| :--- | :--- | :--- | :--- |
| **Fetch Queue Head** | `WHERE class_id = ? AND status = 'WAITING' ORDER BY position ASC LIMIT 1` | `idx_waitlist_fifo_queue (class_id, status, position)` | Index Range Scan (O(1) lookup, no filesort) |
| **Shift Remaining Queue** | `WHERE class_id = ? AND status = 'WAITING' AND position > ?` | `idx_waitlist_fifo_queue (class_id, status, position)` | Targeted Range Update |
| **Active Enrollment Check** | `WHERE class_id = ? AND student_id = ? AND active_enrollment_token IS NOT NULL` | `uq_active_enrollment (class_id, student_id, active_enrollment_token)` | Unique Index Lookup (O(1)) |
| **Active Waitlist Check** | `WHERE class_id = ? AND student_id = ? AND active_waitlist_token IS NOT NULL` | `uq_active_waitlist_entry (class_id, student_id, active_waitlist_token)` | Unique Index Lookup (O(1)) |
| **Notification History** | `WHERE waitlist_entry_id = ? ORDER BY attempt_number ASC` | `uq_entry_attempt (waitlist_entry_id, attempt_number)` | Clustered / Unique Range Scan |
| **Expired Offer Sweeper** | `WHERE status = 'OFFERED' AND offer_expires_at < NOW()` | `idx_waitlist_offer_expiry (status, offer_expires_at)` | Index Range Scan for automated worker |

---
*End of Document. Database Schema Specification prepared for Architecture Approval.*
