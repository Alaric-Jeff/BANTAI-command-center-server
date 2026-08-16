COMMAND CENTER WEB APPLICATION

1. AUTHENTICATION

- Motorcycle mobile application (riders): login/signup via SSO, paired 1:1 with a
  registered hardware device. A device can only be actively paired to one account
  at a time; re-pairing (resale, lost phone, etc.) requires an ownership
  verification step.
- Command Center web application: closed provisioning model. Accounts are not
  self-registered — they are created and managed by an authorized admin. This
  prevents unauthorized or fake responder/admin accounts from entering the system.
- Responders: log in with an account provisioned for them by their branch admin.


2. COMMAND CENTER WEB APPLICATION — OVERVIEW

Represents the totality of participating authorities (e.g., specific police
stations, Barangay 171, Barangay 212, etc.). Used by police stations and
barangays to monitor alerts and their statuses, log incident events, and
dispatch responders.

Core modules:
- Alerts Dashboard
- User Management Dashboard
- Audit Logs Dashboard
- Map Dashboard (live view of responder locations)


3. ENTITIES & ROLES

I. Superadmin
   - Platform-level role, not scoped to any single branch.
   - Held by the development/operations team for the current phase.
   - Responsibilities: creating new branches (police stations, barangays) and
     assigning admins to them.

II. Admin (branch-scoped)
   - Scoped to a single branch (e.g., Police Station Manila, Police Station
     Caloocan). Can only view other admins and responders within their own branch.
   - Responsibilities:
     - Provisioning accounts and roles for responders in their branch
     - Assigning or dispatching responders to a received alert

III. Responder (branch-scoped) — "Default" role
   - Responsibilities:
     - Receives assignments from their branch admin
     - Arrival status is updated automatically based on location proximity to
       the incident (optimal detection radius/threshold to be determined during
       implementation and testing). A manual "Mark as Arrived" fallback is
       provided in the app for cases where automatic detection fails or is
       delayed (e.g., GPS drift, poor signal, indoor/obstructed locations),
       ensuring status is never permanently stuck due to a sensor gap.


4. ALERT VISIBILITY & MULTI-BRANCH HANDLING

Geospatially Bounded Regional Visibility: rather than broadcasting every alert
to every command center (global visibility), each alert is visible only to
branches within a defined radius of the incident — e.g., a 5-10 km bounding
box around the incident location. This avoids blind spots at branch boundaries
(e.g., an incident occurring between Barangay 176 and Barangay 177, where both
fall within each other's bounding box) while preventing stockpiled, irrelevant
alert data from accumulating on command centers that could never realistically
respond (e.g., a Manila incident reaching a Mindanao branch). The radius is
configurable per deployment/branch density and can be tuned during testing.

To avoid redundant or uncoordinated dispatches, each alert tracks a separate
response status per branch rather than a single global status. For example:

  Alert #452
    - Barangay 176: status = Dispatched, responder = Juan D., timestamp = ...
    - Barangay 177: status = Viewing

This lets any branch see in real time whether another branch has already
responded, so admins can make an informed decision — stand down, or send
additional support if the incident warrants multiple units — without the
system forcing a single first-come-first-served lock.

Inter-branch coordination (e.g., confirming who is responding, standing down)
is handled through responders' existing radio/phone protocols, not through an
in-system chat or VoIP feature. This keeps the system focused on situational
awareness and dispatch rather than duplicating communication tools authorities
already use. A lightweight text note field on each alert may be added for
short async context (e.g., "176 already en route, hold back").


5. AUDIT LOGS

Split into distinct modules:
- Incident & Response Logs: alert status changes, dispatch actions, arrival
  confirmations, manual overrides
- System Logs: role changes, account creation/deactivation, branch changes
- (Optional) Access Logs: login events, for accountability on who viewed or
  acted on a given incident