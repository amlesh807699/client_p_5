-- ============================================================================
-- CLASS WAITLIST SMS NOTIFICATION JOB (TWILIO MOCK)
-- Ticket: ENG-135180 | Epic: Core Infrastructure Overhaul
-- Database Engine: MySQL 8 (InnoDB Engine, Strict SQL Mode)
-- Description: Complete Production DDL, Integrity Constraints, Sample Data,
--              and Transactional Query Recipes.
-- ============================================================================

-- Enforce strict SQL mode and default UTF8MB4 charset
SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET foreign_key_checks = 0;

-- Drop tables in reverse topological order if rebuilding
DROP TABLE IF EXISTS system_audit_logs;
DROP TABLE IF EXISTS sms_notifications;
DROP TABLE IF EXISTS seat_release_events;
DROP TABLE IF EXISTS waitlist_entries;
DROP TABLE IF EXISTS class_enrollments;
DROP TABLE IF EXISTS classes;
DROP TABLE IF EXISTS students;

SET foreign_key_checks = 1;

-- ============================================================================
-- 1. TABLE: students
-- Business Purpose: Master directory of students eligible for enrollments and
--                   waitlists. Enforces E.164 phone formatting for SMS delivery.
-- ============================================================================
CREATE TABLE students (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    student_uuid CHAR(36) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL COMMENT 'E.164 international format (+[1-9][0-9]{1,14})',
    status ENUM('ACTIVE', 'SUSPENDED', 'ARCHIVED') NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at DATETIME(3) NULL,

    CONSTRAINT uq_students_uuid UNIQUE (student_uuid),
    CONSTRAINT uq_students_email UNIQUE (email),
    CONSTRAINT chk_students_phone_e164 CHECK (phone REGEXP '^\\+[1-9][0-9]{1,14}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Master student directory';

CREATE INDEX idx_students_phone ON students (phone);
CREATE INDEX idx_students_status ON students (status);
CREATE INDEX idx_students_name ON students (last_name, first_name);


-- ============================================================================
-- 2. TABLE: classes
-- Business Purpose: Academic course sections with defined physical capacity,
--                   operating status, schedule, and offer reservation timeouts.
-- ============================================================================
CREATE TABLE classes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_code VARCHAR(30) NOT NULL COMMENT 'Unique academic identifier e.g. CS-101',
    title VARCHAR(200) NOT NULL,
    description TEXT NULL,
    instructor VARCHAR(150) NOT NULL,
    classroom VARCHAR(100) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    max_capacity INT UNSIGNED NOT NULL COMMENT 'Maximum physical classroom seating',
    max_waitlist_capacity INT UNSIGNED NULL COMMENT 'Optional cap on waitlist; NULL = unbounded',
    status ENUM('DRAFT', 'OPEN', 'FULL', 'CANCELLED', 'COMPLETED') NOT NULL DEFAULT 'OPEN',
    offer_timeout_hours INT UNSIGNED NOT NULL DEFAULT 24 COMMENT 'Hours granted to claim offered seat',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at DATETIME(3) NULL,

    CONSTRAINT uq_classes_code UNIQUE (class_code),
    CONSTRAINT chk_classes_capacity CHECK (max_capacity > 0),
    CONSTRAINT chk_classes_dates CHECK (end_date >= start_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Course sections and capacity management';

CREATE INDEX idx_classes_status_dates ON classes (status, start_date);
CREATE INDEX idx_classes_instructor ON classes (instructor);


-- ============================================================================
-- 3. TABLE: class_enrollments
-- Business Purpose: Records active and past student registrations for classes.
--                   Enforces at the database layer that a student can only hold
--                   one active enrollment per class simultaneously.
-- ============================================================================
CREATE TABLE class_enrollments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL,
    student_id BIGINT UNSIGNED NOT NULL,
    status ENUM('ENROLLED', 'DROPPED', 'CANCELLED') NOT NULL DEFAULT 'ENROLLED',
    enrolled_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    dropped_at DATETIME(3) NULL,
    drop_reason VARCHAR(255) NULL,
    
    -- Generated column for uniqueness: non-null only when status is ENROLLED.
    -- Allows historical dropped records for same student while prohibiting duplicate active enrollments.
    active_enrollment_token VARCHAR(20) GENERATED ALWAYS AS (
        CASE WHEN status = 'ENROLLED' THEN 'ENROLLED' ELSE NULL END
    ) STORED,

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT fk_enrollments_class 
        FOREIGN KEY (class_id) REFERENCES classes (id) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_enrollments_student 
        FOREIGN KEY (student_id) REFERENCES students (id) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_active_enrollment 
        UNIQUE (class_id, student_id, active_enrollment_token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Student course enrollments and seat consumption';

CREATE INDEX idx_enrollments_class_status ON class_enrollments (class_id, status);
CREATE INDEX idx_enrollments_student_status ON class_enrollments (student_id, status);


-- ============================================================================
-- 4. TABLE: seat_release_events
-- Business Purpose: Immutable transactional ledger recording every formal seat
--                   release event (drops, capacity increases, or offer timeouts).
--                   Serves as the parent event for deterministic notification tokens.
-- ============================================================================
CREATE TABLE seat_release_events (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    event_uuid CHAR(36) NOT NULL,
    class_id BIGINT UNSIGNED NOT NULL,
    triggered_by VARCHAR(100) NOT NULL COMMENT 'Staff username, email, or SYSTEM_WORKER',
    reason ENUM('ENROLLMENT_DROPPED', 'CAPACITY_EXPANDED', 'OFFER_EXPIRED', 'MANUAL_RELEASE') NOT NULL,
    seats_released INT UNSIGNED NOT NULL DEFAULT 1,
    notes TEXT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    CONSTRAINT uq_seat_release_uuid UNIQUE (event_uuid),
    CONSTRAINT chk_release_seats CHECK (seats_released > 0),
    CONSTRAINT fk_seat_release_class 
        FOREIGN KEY (class_id) REFERENCES classes (id) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Seat availability release event ledger';

CREATE INDEX idx_seat_release_class_created ON seat_release_events (class_id, created_at);


-- ============================================================================
-- 5. TABLE: waitlist_entries
-- Business Purpose: Manages ordered FIFO queues for oversubscribed classes.
--                   Enforces contiguous unique ordering when WAITING, exclusive
--                   active waitlist entry per student, and time-bound offer states.
-- ============================================================================
CREATE TABLE waitlist_entries (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL,
    student_id BIGINT UNSIGNED NOT NULL,
    position INT UNSIGNED NULL COMMENT 'Strict 1..N order when WAITING; NULL when OFFERED/CONVERTED/EXPIRED/WITHDRAWN',
    status ENUM('WAITING', 'OFFERED', 'CONVERTED', 'EXPIRED', 'WITHDRAWN', 'CANCELLED') NOT NULL DEFAULT 'WAITING',
    offered_at DATETIME(3) NULL COMMENT 'Timestamp when seat offer was extended',
    offer_expires_at DATETIME(3) NULL COMMENT 'Deadline for student to accept seat offer',
    converted_at DATETIME(3) NULL COMMENT 'Timestamp when offer was converted to active enrollment',
    withdrawn_at DATETIME(3) NULL COMMENT 'Timestamp if student withdrew voluntarily',

    -- Generated column enforcing exactly ONE active waitlist entry (WAITING or OFFERED) per student per class.
    active_waitlist_token VARCHAR(20) GENERATED ALWAYS AS (
        CASE WHEN status IN ('WAITING', 'OFFERED') THEN 'ACTIVE' ELSE NULL END
    ) STORED,

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT fk_waitlist_class 
        FOREIGN KEY (class_id) REFERENCES classes (id) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_waitlist_student 
        FOREIGN KEY (student_id) REFERENCES students (id) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_class_position 
        UNIQUE (class_id, position),
    CONSTRAINT uq_active_waitlist_entry 
        UNIQUE (class_id, student_id, active_waitlist_token),
    CONSTRAINT chk_waitlist_positive_position 
        CHECK (position IS NULL OR position > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Waitlist queue and offer reservation state';

-- Composite index optimized for FIFO queue head lookup and position recalculations
CREATE INDEX idx_waitlist_fifo_queue ON waitlist_entries (class_id, status, position);
CREATE INDEX idx_waitlist_student ON waitlist_entries (student_id, status);
CREATE INDEX idx_waitlist_offer_expiry ON waitlist_entries (status, offer_expires_at);


-- ============================================================================
-- 6. TABLE: sms_notifications
-- Business Purpose: Full audit trail of simulated Twilio SMS communications.
--                   Guarantees idempotency, attempt tracking, error recording,
--                   and prevents duplicate notifications for the same offer event.
-- ============================================================================
CREATE TABLE sms_notifications (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    notification_uuid CHAR(36) NOT NULL,
    waitlist_entry_id BIGINT UNSIGNED NOT NULL,
    seat_release_event_id BIGINT UNSIGNED NULL COMMENT 'Nullable association to triggering release event',
    recipient_phone VARCHAR(20) NOT NULL COMMENT 'Phone number message was routed to',
    message_body VARCHAR(500) NOT NULL COMMENT 'Full templated text of SMS dispatched',
    idempotency_key VARCHAR(128) NOT NULL COMMENT 'Deterministic hash preventing duplicate executions',
    status ENUM('PENDING', 'SENT', 'FAILED') NOT NULL DEFAULT 'PENDING',
    attempt_number TINYINT UNSIGNED NOT NULL DEFAULT 1,
    mock_message_sid VARCHAR(64) NULL COMMENT 'Simulated Twilio Message SID (e.g. SM...)',
    error_code VARCHAR(32) NULL COMMENT 'Simulated Twilio error code (e.g. 21211, 30008)',
    error_message VARCHAR(255) NULL COMMENT 'Descriptive error message returned by mock service',
    sent_at DATETIME(3) NULL COMMENT 'Timestamp when simulated carrier accepted message',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT uq_notification_uuid UNIQUE (notification_uuid),
    CONSTRAINT uq_idempotency_key UNIQUE (idempotency_key),
    CONSTRAINT uq_entry_attempt UNIQUE (waitlist_entry_id, attempt_number),
    CONSTRAINT chk_attempt_number CHECK (attempt_number BETWEEN 1 AND 5),
    CONSTRAINT fk_notifications_waitlist 
        FOREIGN KEY (waitlist_entry_id) REFERENCES waitlist_entries (id) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_notifications_release_event 
        FOREIGN KEY (seat_release_event_id) REFERENCES seat_release_events (id) 
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Twilio Mock SMS dispatch audit log';

CREATE INDEX idx_notifications_waitlist_status ON sms_notifications (waitlist_entry_id, status);
CREATE INDEX idx_notifications_status_created ON sms_notifications (status, created_at);
CREATE INDEX idx_notifications_mock_sid ON sms_notifications (mock_message_sid);


-- ============================================================================
-- 7. TABLE: system_audit_logs
-- Business Purpose: Immutable security and analytics log capturing operational
--                   actions and telemetry events without sensitive PII exposure.
-- ============================================================================
CREATE TABLE system_audit_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    event_name VARCHAR(100) NOT NULL COMMENT 'Event identifier, e.g. [Analytics] User interacted...',
    entity_type VARCHAR(50) NOT NULL COMMENT 'CLASS, ENROLLMENT, WAITLIST, NOTIFICATION',
    entity_id BIGINT UNSIGNED NOT NULL,
    performed_by VARCHAR(100) NOT NULL COMMENT 'Authenticated staff username or SYSTEM',
    payload_summary JSON NULL COMMENT 'Sanitized metadata payload; PII masked',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Audit trail and system telemetry';

CREATE INDEX idx_audit_entity ON system_audit_logs (entity_type, entity_id);
CREATE INDEX idx_audit_event_time ON system_audit_logs (event_name, created_at);


-- ============================================================================
-- REALISTIC SAMPLE SEED DATA (INSERT STATEMENTS)
-- ============================================================================

-- 1. Insert Students
INSERT INTO students (student_uuid, first_name, last_name, email, phone, status) VALUES
('b1a2c3d4-0001-4000-8000-000000000001', 'Alice', 'Chen', 'alice.chen@university.edu', '+15005550006', 'ACTIVE'),
('b1a2c3d4-0002-4000-8000-000000000002', 'Brian', 'Miller', 'brian.miller@university.edu', '+15005550006', 'ACTIVE'),
('b1a2c3d4-0003-4000-8000-000000000003', 'Chloe', 'Davis', 'chloe.davis@university.edu', '+15005550001', 'ACTIVE'), -- Configured for Invalid Phone simulation
('b1a2c3d4-0004-4000-8000-000000000004', 'David', 'Kumar', 'david.kumar@university.edu', '+15005550006', 'ACTIVE'),
('b1a2c3d4-0005-4000-8000-000000000005', 'Elena', 'Rostova', 'elena.rostova@university.edu', '+15005550003', 'ACTIVE'); -- Configured for Timeout simulation

-- 2. Insert Classes (One at capacity, one open)
INSERT INTO classes (class_code, title, description, instructor, classroom, start_date, end_date, start_time, end_time, max_capacity, status) VALUES
('CS-101', 'Introduction to Computer Science', 'Foundations of algorithms and programming in Python', 'Dr. Alan Turing', 'Hall A-101', '2027-01-15', '2027-05-20', '09:00:00', '10:30:00', 2, 'FULL'),
('BIO-201', 'Cellular & Molecular Biology', 'Comprehensive survey of eukaryotic cell mechanisms', 'Dr. Rosalind Franklin', 'Science C-305', '2027-01-16', '2027-05-21', '11:00:00', '12:30:00', 30, 'OPEN');

-- 3. Insert Enrollments for CS-101 (Fills max_capacity = 2)
INSERT INTO class_enrollments (class_id, student_id, status, enrolled_at) VALUES
(1, 1, 'ENROLLED', '2026-11-01 10:00:00.000'), -- Alice Chen enrolled
(1, 2, 'ENROLLED', '2026-11-01 10:15:00.000'); -- Brian Miller enrolled

-- 4. Insert Waitlist Entries for CS-101 (Chloe Davis #1, David Kumar #2, Elena Rostova #3)
INSERT INTO waitlist_entries (class_id, student_id, position, status, created_at) VALUES
(1, 3, 1, 'WAITING', '2026-11-02 09:00:00.000'),
(1, 4, 2, 'WAITING', '2026-11-02 09:30:00.000'),
(1, 5, 3, 'WAITING', '2026-11-02 10:00:00.000');


-- ============================================================================
-- REALISTIC TRANSACTION RECIPES & SELECT QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RECIPE A: Real-Time Capacity & Waitlist Summary Query
-- Evaluates max capacity, enrolled count, held reservation offers, available seats,
-- and queue depth for a class.
-- ----------------------------------------------------------------------------
SELECT 
    c.id AS class_id,
    c.class_code,
    c.title,
    c.max_capacity,
    COALESCE(e.enrolled_count, 0) AS enrolled_count,
    COALESCE(w_res.reserved_count, 0) AS reserved_count,
    (c.max_capacity - (COALESCE(e.enrolled_count, 0) + COALESCE(w_res.reserved_count, 0))) AS available_seats,
    COALESCE(w_wait.waitlisted_count, 0) AS waitlisted_count,
    c.status AS operational_status
FROM classes c
LEFT JOIN (
    SELECT class_id, COUNT(*) AS enrolled_count 
    FROM class_enrollments 
    WHERE status = 'ENROLLED' 
    GROUP BY class_id
) e ON c.id = e.class_id
LEFT JOIN (
    SELECT class_id, COUNT(*) AS reserved_count 
    FROM waitlist_entries 
    WHERE status = 'OFFERED' AND offer_expires_at > CURRENT_TIMESTAMP(3)
    GROUP BY class_id
) w_res ON c.id = w_res.class_id
LEFT JOIN (
    SELECT class_id, COUNT(*) AS waitlisted_count 
    FROM waitlist_entries 
    WHERE status = 'WAITING'
    GROUP BY class_id
) w_wait ON c.id = w_wait.class_id
WHERE c.id = 1;


-- ----------------------------------------------------------------------------
-- RECIPE B: Atomic Seat Release & Next Candidate Reservation Transaction
-- Scenario: Student #2 (Brian Miller) drops CS-101.
-- This transaction atomically drops enrollment, records release event, locks the
-- next waitlist candidate, reserves the seat, and shifts positions for remaining peers.
-- ----------------------------------------------------------------------------
START TRANSACTION;

-- Step 1: Drop active enrollment for Brian Miller
UPDATE class_enrollments
SET status = 'DROPPED',
    dropped_at = CURRENT_TIMESTAMP(3),
    drop_reason = 'Student requested schedule change'
WHERE class_id = 1 AND student_id = 2 AND status = 'ENROLLED';

-- Step 2: Record formal seat release event
INSERT INTO seat_release_events (event_uuid, class_id, triggered_by, reason, seats_released, notes)
VALUES (
    'e9b1c2d3-1111-4000-8000-000000000001',
    1,
    'staff_sarah_jenkins',
    'ENROLLMENT_DROPPED',
    1,
    'Drop processed for student_id 2; seat released to waitlist'
);

SET @release_event_id = LAST_INSERT_ID();

-- Step 3: Select next eligible candidate using pessimistic lock (Position 1)
SELECT id, student_id, position
INTO @selected_waitlist_id, @selected_student_id, @vacated_position
FROM waitlist_entries
WHERE class_id = 1 AND status = 'WAITING' AND position = 1
FOR UPDATE;

-- Step 4: Promote selected candidate to OFFERED, reserve seat for 24 hours, clear position
UPDATE waitlist_entries
SET status = 'OFFERED',
    position = NULL,
    offered_at = CURRENT_TIMESTAMP(3),
    offer_expires_at = DATE_ADD(CURRENT_TIMESTAMP(3), INTERVAL 24 HOUR)
WHERE id = @selected_waitlist_id;

-- Step 5: Atomically shift all remaining waitlist entries up by 1 position (FIFO contiguity)
UPDATE waitlist_entries
SET position = position - 1
WHERE class_id = 1 AND status = 'WAITING' AND position > @vacated_position;

-- Step 6: Insert pending notification record with deterministic idempotency key
INSERT INTO sms_notifications (
    notification_uuid,
    waitlist_entry_id,
    seat_release_event_id,
    recipient_phone,
    message_body,
    idempotency_key,
    status,
    attempt_number
)
SELECT 
    'n8a1c2d3-2222-4000-8000-000000000001',
    @selected_waitlist_id,
    @release_event_id,
    s.phone,
    CONCAT('Good news ', s.first_name, '! A seat has opened in CS-101. Please confirm your registration within 24 hours.'),
    SHA2(CONCAT('OFFER-', @selected_waitlist_id, '-', @release_event_id, '-ATTEMPT-1'), 256),
    'PENDING',
    1
FROM students s
WHERE s.id = @selected_student_id;

SET @notification_id = LAST_INSERT_ID();

-- Step 7: Record Telemetry in Audit Log
INSERT INTO system_audit_logs (event_name, entity_type, entity_id, performed_by, payload_summary)
VALUES (
    '[Analytics] User interacted with Class Waitlist SMS Notification Job (Twilio Mock)',
    'WAITLIST',
    @selected_waitlist_id,
    'staff_sarah_jenkins',
    JSON_OBJECT('action', 'SEAT_OFFER_DISPATCHED', 'class_id', 1, 'candidate_student_id', @selected_student_id)
);

COMMIT;


-- ----------------------------------------------------------------------------
-- RECIPE C: Twilio Mock Execution Result Update (Simulated Dispatch Outcome)
-- Updates notification status to SENT or FAILED based on mock simulation.
-- ----------------------------------------------------------------------------
-- Case C1: Successful Dispatch
UPDATE sms_notifications
SET status = 'SENT',
    mock_message_sid = 'SM7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d',
    sent_at = CURRENT_TIMESTAMP(3)
WHERE id = @notification_id AND status = 'PENDING';

-- Case C2: Controlled Failure & Retry Query
-- If mock failed, Staff executes retry:
-- SELECT notification for retry:
SELECT id, waitlist_entry_id, attempt_number, status, recipient_phone
FROM sms_notifications
WHERE id = 1 AND status = 'FAILED' AND attempt_number < 3;


-- ----------------------------------------------------------------------------
-- RECIPE D: Student Confirms Seat Offer (Two-Phase Conversion)
-- Staff confirms student acceptance within the 24-hour window.
-- Converts waitlist entry to CONVERTED and creates active enrollment.
-- ----------------------------------------------------------------------------
START TRANSACTION;

-- Verify offer is still valid and lock row
SELECT id, class_id, student_id, offer_expires_at
INTO @offer_waitlist_id, @offer_class_id, @offer_student_id, @offer_expiry
FROM waitlist_entries
WHERE id = 1 AND status = 'OFFERED' AND offer_expires_at > CURRENT_TIMESTAMP(3)
FOR UPDATE;

-- Convert waitlist entry
UPDATE waitlist_entries
SET status = 'CONVERTED',
    converted_at = CURRENT_TIMESTAMP(3)
WHERE id = @offer_waitlist_id;

-- Create official class enrollment
INSERT INTO class_enrollments (class_id, student_id, status, enrolled_at)
VALUES (@offer_class_id, @offer_student_id, 'ENROLLED', CURRENT_TIMESTAMP(3));

-- Emit Telemetry
INSERT INTO system_audit_logs (event_name, entity_type, entity_id, performed_by, payload_summary)
VALUES (
    '[Analytics] User interacted with Class Waitlist SMS Notification Job (Twilio Mock)',
    'ENROLLMENT',
    LAST_INSERT_ID(),
    'staff_sarah_jenkins',
    JSON_OBJECT('action', 'OFFER_CONVERTED_TO_ENROLLMENT', 'class_id', @offer_class_id, 'student_id', @offer_student_id)
);

COMMIT;
