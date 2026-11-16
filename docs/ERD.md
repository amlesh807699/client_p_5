# Entity Relationship Diagram (ERD)
## Class Waitlist SMS Notification Job (Twilio Mock)
**Ticket ID:** ENG-135180  
**Epic:** Core Infrastructure Overhaul  
**Database Engine:** MySQL 8.0+ (InnoDB)  
**Document File:** `docs/ERD.md`  

---

## 1. Visual Entity Relationship Diagram (Mermaid)

The following Mermaid ER diagram illustrates the complete relational topology, table attributes, primary keys (`PK`), foreign keys (`FK`), unique keys (`UK`), and relationship cardinalities across all entities.

```mermaid
erDiagram
    STUDENTS ||--o{ CLASS_ENROLLMENTS : "has"
    STUDENTS ||--o{ WAITLIST_ENTRIES : "joins"
    CLASSES ||--o{ CLASS_ENROLLMENTS : "enrolls"
    CLASSES ||--o{ WAITLIST_ENTRIES : "queues"
    CLASSES ||--o{ SEAT_RELEASE_EVENTS : "releases_seats_for"
    SEAT_RELEASE_EVENTS ||--o{ SMS_NOTIFICATIONS : "triggers"
    WAITLIST_ENTRIES ||--o{ SMS_NOTIFICATIONS : "notified_via"
    
    STUDENTS {
        bigint_unsigned id PK "Auto Increment"
        char_36 student_uuid UK "External UUID"
        varchar_100 first_name "Legal First Name"
        varchar_100 last_name "Legal Last Name"
        varchar_255 email UK "Academic Email"
        varchar_20 phone "E.164 Phone Format"
        enum status "ACTIVE, SUSPENDED, ARCHIVED"
        datetime_3 created_at "Created Timestamp"
        datetime_3 updated_at "Updated Timestamp"
        datetime_3 deleted_at "Soft Delete Timestamp"
    }

    CLASSES {
        bigint_unsigned id PK "Auto Increment"
        varchar_30 class_code UK "Unique Course Code"
        varchar_200 title "Course Title"
        text description "Course Syllabus Description"
        varchar_150 instructor "Faculty Name"
        varchar_100 classroom "Physical Location"
        date start_date "Term Start"
        date end_date "Term End"
        time start_time "Session Start"
        time end_time "Session Conclusion"
        int_unsigned max_capacity "Seating Limit"
        int_unsigned max_waitlist_capacity "Optional Waitlist Cap"
        enum status "DRAFT, OPEN, FULL, CANCELLED, COMPLETED"
        int_unsigned offer_timeout_hours "Default 24 Hours"
        datetime_3 created_at "Created Timestamp"
        datetime_3 updated_at "Updated Timestamp"
        datetime_3 deleted_at "Soft Delete Timestamp"
    }

    CLASS_ENROLLMENTS {
        bigint_unsigned id PK "Auto Increment"
        bigint_unsigned class_id FK "References classes(id)"
        bigint_unsigned student_id FK "References students(id)"
        enum status "ENROLLED, DROPPED, CANCELLED"
        datetime_3 enrolled_at "Registration Time"
        datetime_3 dropped_at "Drop Time"
        varchar_255 drop_reason "Cancellation Reason"
        varchar_20 active_enrollment_token UK "Generated Column for Uniqueness"
        datetime_3 created_at "Created Timestamp"
        datetime_3 updated_at "Updated Timestamp"
    }

    SEAT_RELEASE_EVENTS {
        bigint_unsigned id PK "Auto Increment"
        char_36 event_uuid UK "External Event UUID"
        bigint_unsigned class_id FK "References classes(id)"
        varchar_100 triggered_by "Staff Username or SYSTEM"
        enum reason "ENROLLMENT_DROPPED, CAPACITY_EXPANDED, OFFER_EXPIRED, MANUAL_RELEASE"
        int_unsigned seats_released "Seats Made Available"
        text notes "Audit Notes"
        datetime_3 created_at "Event Timestamp"
    }

    WAITLIST_ENTRIES {
        bigint_unsigned id PK "Auto Increment"
        bigint_unsigned class_id FK "References classes(id)"
        bigint_unsigned student_id FK "References students(id)"
        int_unsigned position UK "Ordinal Rank (1..N) when WAITING; NULL otherwise"
        enum status "WAITING, OFFERED, CONVERTED, EXPIRED, WITHDRAWN, CANCELLED"
        datetime_3 offered_at "Offer Extended Timestamp"
        datetime_3 offer_expires_at "Offer Expiration Deadline"
        datetime_3 converted_at "Conversion to Enrollment Timestamp"
        datetime_3 withdrawn_at "Withdrawal Timestamp"
        varchar_20 active_waitlist_token UK "Generated Column for Single Active Waitlist"
        datetime_3 created_at "Join Queue Timestamp"
        datetime_3 updated_at "Updated Timestamp"
    }

    SMS_NOTIFICATIONS {
        bigint_unsigned id PK "Auto Increment"
        char_36 notification_uuid UK "External UUID"
        bigint_unsigned waitlist_entry_id FK "References waitlist_entries(id)"
        bigint_unsigned seat_release_event_id FK "References seat_release_events(id)"
        varchar_20 recipient_phone "E.164 Recipient Phone"
        varchar_500 message_body "Dispatched SMS Body"
        varchar_128 idempotency_key UK "Deterministic Hash"
        enum status "PENDING, SENT, FAILED"
        tinyint_unsigned attempt_number UK "Attempt Counter (1..5)"
        varchar_64 mock_message_sid "Simulated Twilio Message SID"
        varchar_32 error_code "Simulated Error Code"
        varchar_255 error_message "Simulated Diagnostic Reason"
        datetime_3 sent_at "Carrier Acceptance Timestamp"
        datetime_3 created_at "Created Timestamp"
        datetime_3 updated_at "Updated Timestamp"
    }

    SYSTEM_AUDIT_LOGS {
        bigint_unsigned id PK "Auto Increment"
        varchar_100 event_name "Telemetry or Action Name"
        varchar_50 entity_type "CLASS, ENROLLMENT, WAITLIST, etc."
        bigint_unsigned entity_id "Target Entity ID"
        varchar_100 performed_by "Staff Username or SYSTEM"
        json payload_summary "Sanitized Non-PII Metadata"
        datetime_3 created_at "Created Timestamp"
    }
```

---

## 2. Cardinality & Relationship Breakdown

### 2.1 Students to Class Enrollments (`STUDENTS` 1 : N `CLASS_ENROLLMENTS`)
- **Cardinality:** One-to-Many (`1 : 0..*`).
- **Description:** A student may have zero or many class enrollments over time.
- **Integrity Rule:** A student can only have **at most one** active enrollment (`status = 'ENROLLED'`) for any single class, enforced by compound unique index `(class_id, student_id, active_enrollment_token)`.

### 2.2 Classes to Class Enrollments (`CLASSES` 1 : N `CLASS_ENROLLMENTS`)
- **Cardinality:** One-to-Many (`1 : 0..*`).
- **Description:** A class has zero or many student enrollments.
- **Integrity Rule:** The total count of active enrollments plus active reservation offers cannot exceed `max_capacity`.

### 2.3 Students to Waitlist Entries (`STUDENTS` 1 : N `WAITLIST_ENTRIES`)
- **Cardinality:** One-to-Many (`1 : 0..*`).
- **Description:** A student can join waitlists for multiple distinct classes.
- **Integrity Rule:** A student can only have **one** active waitlist record (`status IN ('WAITING', 'OFFERED')`) per class, enforced by compound unique index `(class_id, student_id, active_waitlist_token)`.

### 2.4 Classes to Waitlist Entries (`CLASSES` 1 : N `WAITLIST_ENTRIES`)
- **Cardinality:** One-to-Many (`1 : 0..*`).
- **Description:** A class has zero or many waitlist entries.
- **Integrity Rule:** For entries in `WAITING` status, `position` must be uniquely ordered `(class_id, position)` with no duplicate ranks.

### 2.5 Classes to Seat Release Events (`CLASSES` 1 : N `SEAT_RELEASE_EVENTS`)
- **Cardinality:** One-to-Many (`1 : 0..*`).
- **Description:** Every time a student drops, capacity expands, or an offer times out, an immutable event record is created referencing the parent class.

### 2.6 Seat Release Events to SMS Notifications (`SEAT_RELEASE_EVENTS` 1 : N `SMS_NOTIFICATIONS`)
- **Cardinality:** One-to-Many (`1 : 0..*`).
- **Description:** A single seat release event can trigger one or multiple notification dispatches (e.g., if multiple seats were released simultaneously, or if retries occur). Nullable if notification is manually triggered.

### 2.7 Waitlist Entries to SMS Notifications (`WAITLIST_ENTRIES` 1 : N `SMS_NOTIFICATIONS`)
- **Cardinality:** One-to-Many (`1 : 1..*`).
- **Description:** A waitlist entry receives one initial notification attempt when an offer is extended, and may receive subsequent retry records if the mock simulates a failure.
- **Integrity Rule:** Each attempt increments `attempt_number`. The compound constraint `UNIQUE (waitlist_entry_id, attempt_number)` guarantees strict audit sequencing.

---

## 3. GitHub & Renderer Verification

This Mermaid file is formatted using standard GFM (GitHub Flavored Markdown) Mermaid block syntax (````mermaid ... ````) and is verified to render natively on GitHub, GitLab, and Markdown previewers supporting Mermaid v10+.

---
*End of Document. Prepared for Architecture Approval prior to Phase 4 (API Contracts).*
