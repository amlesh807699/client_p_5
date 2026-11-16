# Comprehensive Edge Cases & Failure Recovery Specification
## Class Waitlist SMS Notification Job (Twilio Mock)
**Ticket ID:** ENG-135180  
**Epic:** Core Infrastructure Overhaul  
**Status:** Approved Architecture Baseline (Capstone 1)  

---

## 1. Overview & Failure Handling Principles

This document defines the deterministic behavior, system responses, and recovery strategies for all expected failure modes, boundary conditions, concurrent race scenarios, and external mock anomalies.

Each edge case specifies:
1. **Trigger:** The exact technical or operational condition initiating the scenario.
2. **Expected Behavior:** System logic and database state changes.
3. **Status Response:** HTTP status codes and structured JSON response payloads.
4. **Recovery Strategy:** Remediation actions taken automatically by the system or manually by staff.

---

## 2. Detailed Edge Case Matrix

### 2.1 EC-01: Empty Class Catalog
- **Trigger:** Staff queries `GET /api/classes` before any course sections are created, or when filters yield no matches.
- **Expected Behavior:** System executes query successfully and calculates aggregate capacity as 0. Does not throw an exception or null reference error.
- **Status Response:** `200 OK`
  ```json
  {
    "success": true,
    "data": [],
    "pagination": { "page": 1, "limit": 20, "totalRecords": 0, "totalPages": 0 }
  }
  ```
- **Recovery Strategy:** UI renders a clean empty state card prompting staff to create a new class.

---

### 2.2 EC-02: Empty Waitlist Queue
- **Trigger:** Staff queries `GET /api/classes/{classId}/waitlist` for an existing class that has no students waiting.
- **Expected Behavior:** Returns an empty array with total waitlisted count as 0. If `classId` does not exist, returns `404 Not Found`.
- **Status Response:** `200 OK`
  ```json
  {
    "success": true,
    "data": [],
    "totalWaitlisted": 0
  }
  ```
- **Recovery Strategy:** UI displays "No students currently on waitlist" with clear visual indicator.

---

### 2.3 EC-03: Invalid Student Profile Details
- **Trigger:** Staff attempts to register a student (`POST /api/students`) with missing names, whitespace-only characters, or malformed email.
- **Expected Behavior:** Request payload validation intercepts the request before database execution.
- **Status Response:** `400 Bad Request`
  ```json
  {
    "success": false,
    "error": {
      "code": "VALIDATION_ERROR",
      "message": "Invalid student registration details.",
      "details": [
        { "field": "firstName", "issue": "First name must not be blank." },
        { "field": "email", "issue": "Invalid email address format." }
      ]
    }
  }
  ```
- **Recovery Strategy:** Staff corrects input fields based on returned validation messages.

---

### 2.4 EC-04: Invalid Mobile Phone Number Format
- **Trigger:** Registration submitted with non-E.164 phone number (e.g. `555-1234` or letters).
- **Expected Behavior:** Server validates regex `^\+[1-9]\d{1,14}$`. The database CHECK constraint `chk_students_phone_e164` acts as a secondary defense.
- **Status Response:** `400 Bad Request`
  ```json
  {
    "success": false,
    "error": {
      "code": "INVALID_PHONE_FORMAT",
      "message": "Phone number must comply with international E.164 standards (e.g. +15005550006)."
    }
  }
  ```
- **Recovery Strategy:** Staff enters valid international mobile phone number prefix.

---

### 2.5 EC-05: Duplicate Student Waitlist Registration
- **Trigger:** Staff attempts to place Student A onto the waitlist for Class 101 when Student A already has a `WAITING` or `OFFERED` entry.
- **Expected Behavior:** The compound unique index `uq_active_waitlist_entry (class_id, student_id, active_waitlist_token)` rejects insertion.
- **Status Response:** `409 Conflict`
  ```json
  {
    "success": false,
    "error": {
      "code": "STUDENT_ALREADY_WAITLISTED",
      "message": "Student is already registered on the active waitlist for this course.",
      "details": [{ "field": "studentId", "issue": "Active entry exists with ID 10 in WAITING status." }]
    }
  }
  ```
- **Recovery Strategy:** UI informs staff that the student is already queued and highlights their current position.

---

### 2.6 EC-06: Direct Enrollment Attempt on Full Class
- **Trigger:** Staff calls direct enrollment API (`POST /api/classes/{classId}/enroll`) when $\text{available\_seats} \le 0$.
- **Expected Behavior:** System validates capacity invariant; rejects direct enrollment to prevent overbooking.
- **Status Response:** `400 Bad Request`
  ```json
  {
    "success": false,
    "error": {
      "code": "CLASS_FULL",
      "message": "Course has reached maximum seating capacity. Student must join the waitlist."
    }
  }
  ```
- **Recovery Strategy:** UI redirects staff to prompt: "Class is full. Add student to waitlist?"

---

### 2.7 EC-07: Waitlist Addition Attempt when Seats are Available
- **Trigger:** Staff calls `POST /api/classes/{classId}/waitlist` when `availableSeats > 0`.
- **Expected Behavior:** Waitlists are reserved for oversubscribed classes. Joining waitlist is blocked when open seats exist.
- **Status Response:** `400 Bad Request`
  ```json
  {
    "success": false,
    "error": {
      "code": "CLASS_HAS_AVAILABLE_SEATS",
      "message": "Direct enrollment seats are available. Students should enroll directly rather than waitlisting."
    }
  }
  ```
- **Recovery Strategy:** Staff proceeds with direct enrollment.

---

### 2.8 EC-08: Multiple Simultaneous Seat Releases
- **Trigger:** 3 students drop simultaneously, or staff increases capacity by 5 seats.
- **Expected Behavior:** A single transaction creates a seat release event for $K$ seats, iterates through the top $K$ waitlist entries (`position <= K`), transitions them to `OFFERED`, reserves $K$ seats, and triggers $K$ distinct notifications.
- **Status Response:** `200 OK`
  ```json
  {
    "success": true,
    "data": {
      "seatsReleased": 3,
      "offersIssued": 3,
      "notificationsDispatched": 3
    }
  }
  ```
- **Recovery Strategy:** System shifts remaining queue positions by $-K$.

---

### 2.9 EC-09: Concurrent Staff Actions (Race Condition)
- **Trigger:** Staff Member A and Staff Member B simultaneously attempt to release a single open seat for Class 101.
- **Expected Behavior:** Both transactions attempt to acquire a pessimistic lock:  
  `SELECT id, max_capacity FROM classes WHERE id = :classId FOR UPDATE;`  
  Staff A's transaction secures the lock and processes Candidate #1. Staff B's transaction waits for lock release. When Staff B resumes, it reads the updated state: no seats remain available or Candidate #1 is already `OFFERED`.
- **Status Response:** Staff A receives `200 OK`; Staff B receives `409 Conflict` or graceful notification that zero seats remain unallocated.
- **Recovery Strategy:** Staff B's dashboard auto-refreshes to show the updated seat counts.

---

### 2.10 EC-10: Duplicate Notification Requests (Rapid Double Click)
- **Trigger:** Staff clicks "Dispatch Notification" twice in rapid succession, or network proxy retries the request.
- **Expected Behavior:** Both requests transmit identical `Idempotency-Key` headers. The first creates the row; the second hits `UNIQUE KEY uq_idempotency_key` and is intercepted, returning the cached outcome with header `X-Cache-Lookup: HIT-IDEMPOTENT`.
- **Status Response:** `200 OK` (Duplicate dispatch prevented).
- **Recovery Strategy:** No secondary SMS is generated; carrier charges/mock records are protected.

---

### 2.11 EC-11: Downstream SMS Mock Failure
- **Trigger:** Notification recipient phone is configured to fail (e.g. `+15005550001` or simulated gateway timeout).
- **Expected Behavior:** The student remains in `OFFERED` status holding their seat. The notification record is stored with `status = 'FAILED'`, capturing `error_code = '21211'` and the diagnostic error message.
- **Status Response:** `200 OK` (with status flag indicating notification failure).
- **Recovery Strategy:** Dashboard flags notification with an amber warning icon and enables the "Retry Notification" action.

---

### 2.12 EC-12: Database Connection Loss During Dispatch
- **Trigger:** Database server or network connection drops while a seat release transaction is executing.
- **Expected Behavior:** Transaction is aborted and rolled back by MySQL InnoDB. No orphaned reservation state or dangling notification record is persisted.
- **Status Response:** `500 Internal Server Error` (`DATABASE_CONNECTION_LOST`).
- **Recovery Strategy:** Client displays connection error banner; transaction can be safely re-attempted once connectivity is restored.

---

### 2.13 EC-13: Slow Internet / High Client Latency
- **Trigger:** Client connects over high-latency cellular or degraded campus WiFi.
- **Expected Behavior:** Endpoints are optimized with composite indexes to execute sub-150ms queries on the server. UI displays non-blocking loading skeletons and disables submission buttons to prevent multiple clicks.
- **Status Response:** Standard `200 OK` upon completion.
- **Recovery Strategy:** UI spinner indicates progress; idempotency keys prevent duplicates if client times out prematurely.

---

### 2.14 EC-14: Complete Network Disconnection
- **Trigger:** Client loses network connection mid-request before receiving the HTTP response.
- **Expected Behavior:** If the request reached the server, the transaction commits with the client's `Idempotency-Key`. When connectivity returns and the client retries, the server recognizes the key and returns the committed result without duplicate processing.
- **Status Response:** Cached `200 OK` on reconnection.
- **Recovery Strategy:** Client syncs state smoothly without duplicating waitlist entries or notifications.

---

### 2.15 EC-15: Repeated Notification Retry Failures (Max Retries Exceeded)
- **Trigger:** Staff attempts a 4th retry after 3 failed attempts (`attempt_number >= 3`).
- **Expected Behavior:** System enforces the circuit breaker rule; rejects automated retry.
- **Status Response:** `422 Unprocessable Entity`
  ```json
  {
    "success": false,
    "error": {
      "code": "MAX_RETRIES_EXCEEDED",
      "message": "Maximum retry attempts (3) exceeded for this notification offer. Manual staff intervention required."
    }
  }
  ```
- **Recovery Strategy:** Staff manually calls the student by phone or adjusts the student's contact details in their profile.

---

### 2.16 EC-16: Voluntary Student Withdrawal While Holding Active Offer
- **Trigger:** Student holding an active offer (`status = 'OFFERED'`) declines or withdraws (`DELETE /api/waitlist/{waitlistId}`).
- **Expected Behavior:** Waitlist entry transitions to `WITHDRAWN`. Reserved seat counter decrements (`reserved_count--`). System immediately frees the seat and triggers an offer to the next student in line (`position = 1`).
- **Status Response:** `200 OK` (with next candidate auto-promoted).
- **Recovery Strategy:** Automated queue rollover prevents vacant seat wastage.

---

### 2.17 EC-17: Academic Course Cancellation
- **Trigger:** Operations Manager cancels a course section (`PUT /api/classes/{id}` with `status = 'CANCELLED'`).
- **Expected Behavior:** All active waitlist entries for that class are bulk transitioned to `CANCELLED` status. Positional ranks are cleared.
- **Status Response:** `200 OK`
- **Recovery Strategy:** Audit log records course cancellation event; staff is notified that queue is closed.

---

### 2.18 EC-18: Expired Offer Reservation Window
- **Trigger:** The 24-hour reservation deadline elapses without student confirmation (`offer_expires_at < NOW()`).
- **Expected Behavior:** Scheduled sweeper or lazy evaluation marks entry as `EXPIRED`. Reserved seat returns to class. Next candidate at `position = 1` is promoted to `OFFERED` and notified.
- **Status Response:** Handled by automated background worker; reflected in subsequent `GET /api/classes/{id}/waitlist` calls.
- **Recovery Strategy:** System ensures no seats remain blocked indefinitely due to unresponsive students.

---
*End of Document. Comprehensive Edge Cases & Failure Recovery Specification.*
