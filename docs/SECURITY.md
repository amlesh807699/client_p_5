# Security & Compliance Specification
## Class Waitlist SMS Notification Job (Twilio Mock)
**Ticket ID:** ENG-135180  
**Epic:** Core Infrastructure Overhaul  
**Status:** Approved Architecture Baseline (Capstone 1)  

---

## 1. Threat Modeling & Defense-in-Depth Strategy

The Class Waitlist SMS Notification platform processes student educational records, personal phone numbers, and administrative enrollment actions. Security is designed following the **OWASP Top 10** guidelines and defense-in-depth principles across all architectural tiers.

---

## 2. SQL Injection Prevention

### 2.1 Mandatory Parameterization (Prepared Statements)
All database interactions must utilize parameterized queries / prepared statements executed through an ACID-compliant driver or Object-Relational Mapper (ORM). 

**Strict Architectural Mandate:**
- Raw SQL string concatenation, template string interpolation (`SELECT * FROM students WHERE id = ${id}`), or un-escaped user inputs are strictly prohibited.
- Dynamic query fragments for sorting or filtering must use strict server-side whitelists:
  ```typescript
  const ALLOWED_SORT_COLUMNS = ['class_code', 'title', 'start_date', 'max_capacity'] as const;
  if (!ALLOWED_SORT_COLUMNS.includes(userSortField)) {
    throw new ValidationError('Invalid sort column');
  }
  ```

---

## 3. Cross-Site Scripting (XSS) Prevention & Output Encoding

### 3.1 Input Sanitization vs. Context-Aware Output Encoding
In accordance with modern enterprise security standards:
- **Input Sanitization Must Not Replace Context-Aware Output Encoding:** Input sanitization alone is insufficient and can mutate valid user data. The system stores user input in its authentic form (after trimming and validation).
- **Context-Aware Output Encoding:** When rendering data to the frontend (React), all user-controlled text (e.g. course titles, student names, notes) is automatically escaped by React's JSX engine.
- Direct insertion of raw HTML (`dangerouslySetInnerHTML`) is banned.
- Server responses must include HTTP security headers:
  ```http
  Content-Security-Policy: default-src 'self'; script-src 'self'; object-src 'none';
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  ```

---

## 4. Sensitive Data Protection & PII Masking

### 4.1 Masked Telephone Numbers in Standard Staff Views
Student phone numbers are Personally Identifiable Information (PII) protected under privacy regulations. In general administrative list views, phone numbers must be masked:
- Stored internally as: `+15005550006`
- Rendered in general waitlist tables as: `+1500555***6`
- Full numbers are only accessible in the individual student profile view by authorized personnel.

### 4.2 Scrubbed Telemetry & Audit Logs
The system emits operational telemetry events such as:
`[Analytics] User interacted with Class Waitlist SMS Notification Job (Twilio Mock)`
- Telemetry log payloads **must never** log raw phone numbers, email addresses, or student names.
- Telemetry events log only synthetic primary keys (`class_id`, `waitlist_entry_id`) and operational action codes.

---

## 5. Zero-Secret Architecture & Credential Management

- During this Capstone and the Twilio Mock phase, **no live Twilio Account SID, Auth Token, or production API keys are stored in the codebase or database**.
- Future production credentials must be injected at runtime via environment variables (`process.env.TWILIO_AUTH_TOKEN`) or a cloud secrets manager (e.g. Google Secret Manager / HashiCorp Vault), never committed to Git.

---

## 6. Authentication & Role-Based Access Control (RBAC)

All endpoints under `/api` require a valid JSON Web Token (JWT) in the `Authorization: Bearer <token>` header.

| Permission / Action | Academic Staff | Operations Manager | System Worker |
| :--- | :---: | :---: | :---: |
| View Classes & Capacity | Allowed | Allowed | Allowed |
| View Waitlist Queue | Allowed | Allowed | Allowed |
| Place Student on Waitlist | Allowed | Allowed | Denied |
| Release Seats Manually | Allowed | Allowed | Denied |
| Confirm Student Offer | Allowed | Allowed | Denied |
| Retry Failed Notification | Allowed | Allowed | Allowed |
| Alter Class Capacity Limits | Denied | Allowed | Denied |
| Cancel Academic Course | Denied | Allowed | Denied |
| Sweep Expired Offers | Denied | Allowed | Allowed |

---
*End of Document. Security & Compliance Specification.*
