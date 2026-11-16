# REST API Contracts Specification
## Class Waitlist SMS Notification Job (Twilio Mock)
**Ticket ID:** ENG-135180  
**Epic:** Core Infrastructure Overhaul  
**API Specification:** RESTful JSON, OpenAPI 3.0.3  
**Base URL:** `/api`  
**OpenAPI Specification Artifact:** [`docs/openapi.yaml`](file:///c:/Users/amles/Desktop/tw/docs/openapi.yaml)  

---

## 1. Global Architectural & Protocol Standards

### 1.1 HTTP Headers & Content Negotiation
- **Content-Type:** `application/json; charset=utf-8` (Mandatory for all `POST` and `PUT` request bodies).
- **Accept:** `application/json`
- **Idempotency-Key:** Optional on general endpoints, **Mandatory** on `POST /api/waitlist/{waitlistId}/notifications` and `POST /api/classes/{classId}/seats/release`. Format: UUID v4 or cryptographic hash string (e.g. `Idempotency-Key: 7f8c1b2a-3c4d-5e6f-7a8b-9c0d1e2f3a4b`).
- **Authorization:** `Bearer <token>` (Staff or Operations Manager JWT).

### 1.2 Standardized JSON Envelope Formats

#### 1.2.1 Success Envelope (Single Entity)
```json
{
  "success": true,
  "data": {
    "id": 1,
    "classCode": "CS-101",
    "title": "Introduction to Computer Science"
  },
  "timestamp": "2026-11-14T10:00:00.000Z",
  "requestId": "req_8a7b6c5d4e3f"
}
```

#### 1.2.2 Success Envelope (Paginated Collection)
```json
{
  "success": true,
  "data": [ ... ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "totalRecords": 85,
    "totalPages": 5,
    "hasNextPage": true,
    "hasPrevPage": false
  },
  "timestamp": "2026-11-14T10:00:00.000Z",
  "requestId": "req_8a7b6c5d4e3f"
}
```

#### 1.2.3 Error Envelope (RFC 7807 Enterprise Adaptation)
```json
{
  "success": false,
  "error": {
    "code": "DUPLICATE_WAITLIST_ENTRY",
    "message": "Student is already registered on the active waitlist for this course.",
    "details": [
      {
        "field": "studentId",
        "issue": "Student ID 3 currently occupies position 1 in WAITING status."
      }
    ]
  },
  "timestamp": "2026-11-14T10:00:00.000Z",
  "requestId": "req_8a7b6c5d4e3f"
}
```

---

## 2. API Endpoints Catalog

| Domain | Method | URL Path | Description & Concurrency Scope |
| :--- | :--- | :--- | :--- |
| **Classes** | `GET` | `/api/classes` | List courses with capacity, enrolled, reserved, and available metrics. |
| **Classes** | `GET` | `/api/classes/{classId}` | Get deep details for a single course section. |
| **Classes** | `POST` | `/api/classes` | Create a new academic course section. |
| **Classes** | `PUT` | `/api/classes/{classId}` | Update course schedule, title, or capacity. |
| **Students** | `GET` | `/api/students` | Search and list student directory with E.164 phone numbers. |
| **Students** | `POST` | `/api/students` | Register a new student profile with phone validation. |
| **Students** | `GET` | `/api/students/{studentId}` | Retrieve student profile with current enrollments & waitlists. |
| **Enrollment** | `POST` | `/api/classes/{classId}/enroll` | Direct enrollment when `availableSeats > 0`. |
| **Enrollment** | `POST` | `/api/classes/{classId}/enrollments/{enrollmentId}/drop` | Drop an enrollment and flag seat as eligible for release. |
| **Waitlist** | `POST` | `/api/classes/{classId}/waitlist` | Add student to waitlist (FIFO ordinal positioning). |
| **Waitlist** | `GET` | `/api/classes/{classId}/waitlist` | List active waitlist queue for a class ordered by position. |
| **Waitlist** | `GET` | `/api/waitlist/{waitlistId}` | Get single waitlist entry details, status, and notification history. |
| **Waitlist** | `DELETE`| `/api/waitlist/{waitlistId}` | Voluntarily withdraw candidate; triggers atomic queue shift. |
| **Waitlist** | `POST` | `/api/waitlist/{waitlistId}/confirm` | Two-phase conversion: confirm student acceptance into class. |
| **Seat Allocation**| `POST` | `/api/classes/{classId}/seats/release` | Atomic seat release trigger; selects candidate & dispatches SMS. |
| **Notifications** | `POST` | `/api/waitlist/{waitlistId}/notifications` | Explicit trigger or re-send of simulated SMS offer notification. |
| **Notifications** | `POST` | `/api/notifications/{notificationId}/retry` | Retry a failed notification attempt (up to 3 total attempts). |
| **Notifications** | `GET` | `/api/notifications` | Query SMS audit log across classes and recipients. |
| **Notifications** | `GET` | `/api/notifications/{notificationId}` | Retrieve single SMS dispatch record with simulated Twilio payload. |

---

## 3. Detailed Endpoint Contracts

### 3.1 Class Management APIs

#### `GET /api/classes`
- **Purpose:** Retrieve list of classes with calculated real-time capacity and waitlist counts.
- **Query Parameters:**
  - `page` (integer, default: 1)
  - `limit` (integer, default: 20, max: 100)
  - `status` (string, optional: `OPEN`, `FULL`, `CANCELLED`, `DRAFT`)
  - `search` (string, optional: course code or title)
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "classCode": "CS-101",
      "title": "Introduction to Computer Science",
      "instructor": "Dr. Alan Turing",
      "classroom": "Hall A-101",
      "startDate": "2027-01-15",
      "endDate": "2027-05-20",
      "startTime": "09:00:00",
      "endTime": "10:30:00",
      "maxCapacity": 30,
      "enrolledCount": 30,
      "reservedCount": 0,
      "availableSeats": 0,
      "waitlistedCount": 5,
      "status": "FULL"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "totalRecords": 1,
    "totalPages": 1
  }
}
```

#### `GET /api/classes/{classId}`
- **Purpose:** Get full details, capacity metrics, and schedule for a specific class.
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "classCode": "CS-101",
    "title": "Introduction to Computer Science",
    "description": "Foundations of algorithms and Python programming",
    "instructor": "Dr. Alan Turing",
    "classroom": "Hall A-101",
    "startDate": "2027-01-15",
    "endDate": "2027-05-20",
    "startTime": "09:00:00",
    "endTime": "10:30:00",
    "maxCapacity": 30,
    "enrolledCount": 28,
    "reservedCount": 1,
    "availableSeats": 1,
    "waitlistedCount": 4,
    "status": "OPEN",
    "offerTimeoutHours": 24,
    "createdAt": "2026-11-01T10:00:00.000Z",
    "updatedAt": "2026-11-14T08:30:00.000Z"
  }
}
```
- **Error Responses:** `404 Not Found` (`CLASS_NOT_FOUND`).

#### `POST /api/classes`
- **Purpose:** Create a new academic class section.
- **Request Body:**
```json
{
  "classCode": "MATH-201",
  "title": "Linear Algebra & Applications",
  "description": "Vector spaces, matrices, eigenvalues and eigenvectors",
  "instructor": "Dr. Katherine Johnson",
  "classroom": "Science Hall 204",
  "startDate": "2027-01-15",
  "endDate": "2027-05-20",
  "startTime": "14:00:00",
  "endTime": "15:30:00",
  "maxCapacity": 25,
  "offerTimeoutHours": 24
}
```
- **Response `201 Created`:** Returns created class object with HTTP `Location: /api/classes/2`.
- **Error Responses:**
  - `400 Bad Request` (`VALIDATION_ERROR`: Missing field, negative capacity, end date before start date).
  - `409 Conflict` (`CLASS_CODE_EXISTS`: Course code already in use).

---

### 3.2 Student Management APIs

#### `GET /api/students`
- **Purpose:** List students with pagination and query filters.
- **Query Parameters:** `page`, `limit`, `search` (matches first name, last name, email, or phone).
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "studentUuid": "b1a2c3d4-0001-4000-8000-000000000001",
      "firstName": "Alice",
      "lastName": "Chen",
      "email": "alice.chen@university.edu",
      "phone": "+15005550006",
      "status": "ACTIVE"
    }
  ]
}
```

#### `POST /api/students`
- **Purpose:** Register a student profile with E.164 phone number formatting.
- **Request Body:**
```json
{
  "firstName": "David",
  "lastName": "Kumar",
  "email": "david.kumar@university.edu",
  "phone": "+15005550006"
}
```
- **Validation Rules:**
  - `firstName`, `lastName`: Required, 1..100 characters, non-whitespace.
  - `email`: Required, valid RFC 5322 email format.
  - `phone`: Required, matches `^\+[1-9]\d{1,14}$`.
- **Response `201 Created`:** Returns created student entity.
- **Error Responses:**
  - `400 Bad Request` (`INVALID_PHONE_FORMAT`, `INVALID_EMAIL_FORMAT`).
  - `409 Conflict` (`EMAIL_ALREADY_EXISTS`).

---

### 3.3 Waitlist Management APIs

#### `POST /api/classes/{classId}/waitlist`
- **Purpose:** Add an eligible student to the waitlist when a class is full.
- **Request Body:**
```json
{
  "studentId": 4
}
```
- **Business Logic & Invariants:**
  1. Validates `classes.id` exists and is in `OPEN` or `FULL` status.
  2. Confirms `availableSeats <= 0`. If `availableSeats > 0`, rejects with `400 Bad Request` (`CLASS_HAS_AVAILABLE_SEATS`).
  3. Verifies student is not already actively enrolled (`400 Bad Request: STUDENT_ALREADY_ENROLLED`).
  4. Verifies student is not already actively waitlisted (`409 Conflict: STUDENT_ALREADY_WAITLISTED`).
  5. Computes `position = COALESCE(MAX(position), 0) + 1` for the class.
- **Response `201 Created`:**
```json
{
  "success": true,
  "data": {
    "waitlistId": 12,
    "classId": 1,
    "classCode": "CS-101",
    "studentId": 4,
    "studentName": "David Kumar",
    "position": 3,
    "status": "WAITING",
    "createdAt": "2026-11-14T10:15:00.000Z"
  }
}
```

#### `GET /api/classes/{classId}/waitlist`
- **Purpose:** List the active waitlist queue for a class in strictly ordered FIFO sequence.
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": [
    {
      "waitlistId": 10,
      "position": 1,
      "studentId": 3,
      "studentName": "Chloe Davis",
      "phoneMasked": "+1500555***1",
      "status": "WAITING",
      "createdAt": "2026-11-02T09:00:00.000Z"
    },
    {
      "waitlistId": 11,
      "position": 2,
      "studentId": 4,
      "studentName": "David Kumar",
      "phoneMasked": "+1500555***6",
      "status": "WAITING",
      "createdAt": "2026-11-02T09:30:00.000Z"
    }
  ],
  "totalWaitlisted": 2
}
```

#### `DELETE /api/waitlist/{waitlistId}`
- **Purpose:** Voluntarily withdraw a student from the waitlist.
- **Concurrency & Re-Indexing:** Atomically transitions status to `WITHDRAWN`, sets `position = NULL`, sets `withdrawnAt = NOW()`, and decrements `position = position - 1` for all subsequent waiting peers.
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": {
    "waitlistId": 10,
    "status": "WITHDRAWN",
    "vacatedPosition": 1,
    "subsequentEntriesShifted": 1
  }
}
```

#### `POST /api/waitlist/{waitlistId}/confirm`
- **Purpose:** **Two-Phase Confirmation Action.** Staff records student verbal/email acceptance of an active seat offer.
- **Pre-Conditions:** `waitlist_entries.status == 'OFFERED'` and `offer_expires_at > NOW()`.
- **Transactional Effects:**
  1. Locks waitlist row `FOR UPDATE`.
  2. Updates waitlist status to `CONVERTED`.
  3. Inserts new record into `class_enrollments` (`status = 'ENROLLED'`).
  4. Class `reserved_count` decreases by 1; `enrolled_count` increases by 1.
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": {
    "waitlistId": 10,
    "status": "CONVERTED",
    "enrollmentId": 35,
    "classId": 1,
    "studentId": 3,
    "confirmedAt": "2026-11-14T11:00:00.000Z"
  }
}
```
- **Error Responses:**
  - `400 Bad Request` (`OFFER_NOT_IN_OFFERED_STATE`).
  - `410 Gone` (`OFFER_EXPIRED`: Offer deadline elapsed; seat has been recycled).

---

### 3.4 Seat Release & Twilio Mock Notification APIs

#### `POST /api/classes/{classId}/seats/release`
- **Purpose:** Administrative action triggering atomic seat vacancy evaluation and automated SMS offer dispatch to the next eligible student.
- **Request Headers:** `Idempotency-Key` (Recommended).
- **Request Body:**
```json
{
  "seatsToRelease": 1,
  "reason": "MANUAL_RELEASE",
  "notes": "Seat opened following academic advisor schedule re-assignment"
}
```
- **Execution Flow (Pessimistic Transaction):**
  1. Acquires row lock on class (`FOR UPDATE`).
  2. Creates entry in `seat_release_events`.
  3. Evaluates waitlist queue: selects candidate at `position = 1` (`FOR UPDATE`).
  4. If candidate found:
     - Sets candidate `status = 'OFFERED'`, `position = NULL`, `offer_expires_at = NOW() + 24h`.
     - Shifts remaining queue positions (`position = position - 1`).
     - Invokes Twilio Mock Service.
     - Logs simulated outcome in `sms_notifications`.
     - Emits Telemetry event.
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": {
    "seatReleaseEventId": 5,
    "seatsReleased": 1,
    "candidatePromoted": {
      "waitlistId": 10,
      "studentId": 3,
      "studentName": "Chloe Davis",
      "status": "OFFERED",
      "offerExpiresAt": "2026-11-15T11:00:00.000Z"
    },
    "notification": {
      "notificationId": 8,
      "status": "SENT",
      "mockMessageSid": "SM7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
      "attemptNumber": 1,
      "recipientPhone": "+15005550006"
    }
  }
}
```

#### `POST /api/notifications/{notificationId}/retry`
- **Purpose:** Re-attempt delivery of a failed simulated SMS notification.
- **Pre-Conditions:** Existing record has `status = 'FAILED'` and `attempt_number < 3`.
- **Request Headers:** `Idempotency-Key: <unique-hash>`
- **Response `200 OK` (Retry Succeeded):**
```json
{
  "success": true,
  "data": {
    "notificationId": 9,
    "previousNotificationId": 8,
    "waitlistEntryId": 10,
    "attemptNumber": 2,
    "status": "SENT",
    "mockMessageSid": "SM8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e",
    "sentAt": "2026-11-14T11:05:00.000Z"
  }
}
```
- **Error Responses:**
  - `400 Bad Request` (`NOTIFICATION_ALREADY_SENT`: Notification is already in `SENT` status).
  - `422 Unprocessable Entity` (`MAX_RETRIES_EXCEEDED`: Max 3 attempts reached; manual intervention required).

#### `GET /api/notifications`
- **Purpose:** Audit history of all simulated SMS notification dispatches.
- **Query Parameters:**
  - `page`, `limit`
  - `status` (`PENDING`, `SENT`, `FAILED`)
  - `waitlistEntryId` (integer, optional)
- **Response `200 OK`:**
```json
{
  "success": true,
  "data": [
    {
      "id": 8,
      "notificationUuid": "n8a1c2d3-2222-4000-8000-000000000001",
      "waitlistEntryId": 10,
      "recipientPhone": "+15005550001",
      "messageBody": "Good news Chloe! A seat has opened in CS-101. Please confirm your registration within 24 hours.",
      "status": "FAILED",
      "attemptNumber": 1,
      "mockMessageSid": null,
      "errorCode": "21211",
      "errorMessage": "Invalid 'To' Phone Number (Simulated)",
      "createdAt": "2026-11-14T10:00:00.000Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "totalRecords": 1
  }
}
```

---

## 4. Idempotency & Concurrency Guarantees

### 4.1 Idempotency Mechanics
When a client sends an `Idempotency-Key` header with a notification dispatch:
1. The server computes a unique digest:  
   $$\text{digest} = \text{SHA-256}(\text{client\_key} \parallel \text{waitlist\_id})$$
2. If the key exists in `sms_notifications.idempotency_key`, the transaction intercepts the duplicate before contacting the mock service, returning the previously generated response with header:  
   `X-Cache-Lookup: HIT-IDEMPOTENT`
3. Prevents duplicate simulated SMS dispatches during client network timeouts or double-clicks.

### 4.2 Error Handling & HTTP Status Codes Summary

| HTTP Code | Error Code | Meaning & Corrective Action |
| :--- | :--- | :--- |
| **`400 Bad Request`** | `VALIDATION_ERROR` | Request payload failed schema validation (e.g., malformed E.164 phone). |
| **`400 Bad Request`** | `CLASS_HAS_AVAILABLE_SEATS` | Waitlist join attempted on a class with available seats; student should enroll directly. |
| **`404 Not Found`** | `RESOURCE_NOT_FOUND` | Class, student, or waitlist ID does not exist in database. |
| **`409 Conflict`** | `STUDENT_ALREADY_WAITLISTED` | Student already has an active (`WAITING` or `OFFERED`) waitlist entry for the course. |
| **`409 Conflict`** | `CONCURRENT_SEAT_CLAIM` | The seat was claimed by another transaction during processing. |
| **`410 Gone`** | `OFFER_EXPIRED` | The 24-hour reservation window for this waitlist offer has elapsed. |
| **`422 Unprocessable`**| `MAX_RETRIES_EXCEEDED` | Notification has failed 3 times; cannot retry automatically. |
| **`500 Internal Error`**| `DATABASE_ERROR` | Transaction failure or unhandled exception; state rolled back cleanly. |

---
*End of Document. Prepared for Architecture Approval prior to Phase 5 (Business Logic, Edge Cases, Security & Twilio Mock).*
