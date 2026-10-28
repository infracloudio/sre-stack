# Feature Specification: Alert Rules for the Demo Shop on Azure

**Feature Branch**: `009-robot-shop-alert-rules`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "Story #122 — Keep: add alert rules for robot-shop. Add alert rules for the demo shop so a fault raises alerts."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Alerts fire when the cart runs out of memory (Importance: must have)

A person demonstrating the demo shop on Azure starts the existing cart memory fault while the load generator is running. Today nothing in the monitoring system reacts. After this story, the monitoring system's alerts page shows alerts for what the fault breaks: the cart being stopped for using too much memory, the cart restarting again and again, the cart having no ready copy, and the shop's website returning server errors because the cart is down.

**Why this priority**: This is the whole point of the story. Without alerts, the later stories (sending alerts to a tool, grouping them, posting to Slack) have nothing to work with.

**Independent Test**: Start the load generator, start the cart memory fault, and open the alerts page. It can be fully tested without any of the later stories, and it delivers the first visible "something is wrong" signal.

**Acceptance Scenarios**:

1. **Given** the shop and monitoring are running on Azure, the load generator is running and no fault is active, **When** the person starts the cart memory fault, **Then** the alerts page shows an alert for the cart being stopped for using too much memory, one for the cart restarting, one for the cart having no ready copy, and one for a high share of server errors.
2. **Given** those alerts are showing, **When** the person removes the fault, **Then** every one of those alerts clears on its own.
3. **Given** an alert is showing, **When** the person reads it, **Then** it says which shop service it is about, which part of the shop it belongs to, and how serious it is, using one of the five severity levels the later alert tool understands (critical, error, high, warning, info).

---

### User Story 2 - Alerts fire when the shop's database is slow (Importance: should have)

The same person starts the existing slow-database fault. After this story, the alerts page shows slow-request alerts for the two shop requests that this fault slows down: the shipping cost lookup and the ratings lookup.

**Why this priority**: It covers the second fault the demo already has, and it proves the slow-request alert works. It comes after the cart fault because the cart fault already needs four of the five alerts.

**Independent Test**: Start the load generator, start the slow-database fault, and open the alerts page. It stands alone: it needs only the shop, monitoring and the load generator.

**Why shipping and ratings, and not payment (this differs from story #122)**: The story as filed names the payment service as the one to watch. Live research (`research.md`, Finding 4) showed payment is slow and uneven even with no fault (a typical payment request takes about 0.6 to 1.0 seconds and the slow tail reaches 1 to 7 seconds), and it did not get slower during the slow-database fault. An alert on payment would fire with no fault, or not at all. Shipping and ratings are the requests the slow-database fault slows down, and they separate clearly: ratings went from about 0.14 seconds to about 1.5 seconds. The developer agreed on 2026-10-27 to use shipping and ratings and drop payment. This is a deliberate change from the story text, not a gap.

**Acceptance Scenarios**:

1. **Given** the shop and monitoring are running, the load generator is running and no fault is active, **When** the person starts the slow-database fault, **Then** the alerts page shows a slow-request alert for the shipping cost lookup and one for the ratings lookup.
2. **Given** those alerts are showing, **When** the person removes the fault, **Then** both alerts clear on their own.
3. **Given** the cart memory fault is running (and the database fault is not), **When** the person looks at the alerts page, **Then** the slow-request alerts for shipping and ratings are not showing.

---

### User Story 3 - A healthy shop raises no alerts (Importance: must have)

The person leaves the shop running under the load generator with no fault for 30 minutes. The alerts page must show nothing firing. An alert that fires on a healthy shop would make every later demo noisy and make people stop trusting it.

**Why this priority**: Alerts that fire without a fault are worse than no alerts. Story #122 requires this explicitly, and Findings 3 and 4 showed the risk is real: a rule on payment latency would have fired with no fault.

**Independent Test**: Start the load generator, make sure no fault is active, wait 30 minutes, and read the alerts page.

**Acceptance Scenarios**:

1. **Given** the shop and monitoring are running, the load generator is running and no fault is active, **When** 30 minutes pass, **Then** no alert from this story fires at any point in those 30 minutes.
2. **Given** a fault has just been removed, **When** the shop recovers, **Then** the alerts clear and stay clear (they do not flap on and off).

---

### User Story 4 - Rules come with the setup and can be changed (Importance: nice to have)

A person who runs the demo wants the alert rules to be there after the normal one-shot Azure setup, with nothing extra to do. They also want to change how sensitive an alert is (for example, raise the slow-request limit). They change the rule and apply it with one command. It must not mean reinstalling or upgrading the whole monitoring system.

**Why this priority**: It makes the rules easy to install and tune. It matters less than the alerts themselves.

**Independent Test**: Run the one-shot Azure setup on a new cluster and see the six rules on the alerts page. Then change one limit, apply it, and see the changed rule on the alerts page without restarting the monitoring system.

**Acceptance Scenarios**:

1. **Given** the alert rules are in place, **When** the person changes one limit and applies the change, **Then** the alerts page uses the new limit without the monitoring system being reinstalled.
2. **Given** the local (k3d) setup or the AWS setup, **When** they are set up, **Then** they behave exactly as before and do not get these alert rules.
3. **Given** a new Azure cluster with nothing installed, **When** the person runs the one-shot Azure setup, **Then** it finishes with all six alert rules already in place and no extra step is needed.

## Requirements *(mandatory)*

### Functional Requirements

Each requirement has an ID. "FR" stands for Functional Requirement, and the number only keeps them in order so later steps can point at one. Each one starts with what it says in plain words.

**Which alerts exist**

- **FR-001 — Out-of-memory alert.** The monitoring system MUST raise an alert when any shop service's container is stopped for using more memory than it is allowed.
- **FR-002 — Restart alert.** It MUST raise an alert when a shop service's container keeps restarting. One example: the cart restarts several times in a few minutes.
- **FR-003 — No-ready-copy alert.** It MUST raise an alert when a shop service has fewer working copies than it should have.
- **FR-004 — Server-error alert.** It MUST raise an alert when a high share of a shop service's requests are answered with a server error. The alert looks at the share of requests, not the raw count, and it ignores a service that receives very few requests, so one failure out of two requests does not raise it.
- **FR-005 — Slow-request alerts.** It MUST raise an alert when the shipping cost lookup is slow, and a separate alert when the ratings lookup is slow. Like the server-error alert, these MUST NOT fire when the service has received only a handful of requests, so a few slow requests out of a few do not raise an alert. Payment is deliberately not covered (see Story 2 and Assumptions).
- **FR-006 — Shop only.** All of these alerts MUST be about the demo shop's services only. They do not cover the traffic demo (hotrod), the monitoring tools, or anything else in the cluster.

**What every alert tells you**

- **FR-007 — Names its service.** Every alert MUST say which shop service it is about (for example "cart") and which part of the cluster that service runs in.
- **FR-008 — Has a severity.** Every alert MUST carry one severity, and it MUST be one of the five levels the later alert tool understands: critical, error, high, warning, info.

**How alerts behave**

- **FR-009 — No false alarms from a blip.** An alert MUST fire only after its condition has stayed true for a short, set time. A condition that lasts a few seconds does not raise an alert.
- **FR-010 — Clears by itself.** When the condition ends, the alert MUST clear without anyone doing anything.
- **FR-011 — Quiet when healthy.** With the shop running under the load generator and no fault active, none of these alerts MAY fire.
- **FR-012 — Limits are tuned and explained.** The limits for the slow-request alerts and the server-error alert MUST be chosen from measured normal behaviour. The chosen values and the reason for each MUST be written down where a person changing them will see them.

**Where and how they are installed**

- **FR-013 — Azure only.** The alert rules MUST be installed on the Azure setup only. The local (k3d) setup and the AWS setup MUST keep their existing behavior and MUST NOT install these rules. Shared setup files and documentation MAY change to add and explain the Azure-only step, provided those changes do not affect either other setup.
- **FR-014 — Part of the one-shot Azure setup.** The rules MUST be installed by the one-shot Azure setup, the single command that deploys the whole Azure stack, with no extra manual step. They are added to the Azure monitoring setup that the one-shot setup already runs, so running that part on its own installs them too. Running either a second time MUST succeed. On that second run, this story's alert-rule step MUST create nothing new and leave the installed rules unchanged. This does not promise that the rest of the existing monitoring setup leaves no record of being run again.
- **FR-015 — Change without reinstalling.** A person MUST be able to change a rule and apply it with one command, without reinstalling or upgrading the monitoring system.

**What must not change**

- **FR-016 — Existing rule left alone.** The one alert rule that already exists in the shared monitoring settings (for the Bookinfo sample app, which this demo does not use) MUST NOT be changed or removed by this story. It is recorded as a follow-up for a later story.
- **FR-017 — Everything else keeps working.** The cart memory fault and the slow-database fault MUST still start and revert exactly as they do today. The existing monitoring (metrics, dashboards, traces) MUST keep working, and the repository's lint check MUST still pass.

## Success Criteria *(mandatory)*

### Measurable Outcomes

"SC" stands for Success Criterion. Each one says what a person can check and the number that means it passed. Six alerts exist in total: out of memory, restarting, no ready copy, high share of server errors, slow shipping lookup, slow ratings lookup. The times below are targets, and the live run confirms them or they are changed with a reason written down.

- **SC-001 — The cart fault is seen.** With the load generator running, starting the cart memory fault makes 4 of 4 expected alerts show as firing (out of memory, restarting, no ready copy, server errors) within 5 minutes.
- **SC-002 — The database fault is seen.** With the load generator running, starting the slow-database fault makes both slow-request alerts (shipping and ratings) show as firing within 5 minutes.
- **SC-003 — A healthy shop stays quiet.** With the load generator running and no fault, 0 alerts from this story fire at any point in 30 minutes.
- **SC-004 — Alerts clear and stay clear.** After either fault is removed, every alert it raised clears within 10 minutes, and none comes back in the next 10 minutes.
- **SC-005 — Each fault raises only its own alerts.** During the cart memory fault, 0 of the 2 slow-request alerts fire. During the slow-database fault, 0 of the out-of-memory, restarting and no-ready-copy alerts fire.
- **SC-006 — Every alert is readable.** 6 of 6 alerts name their shop service and the part of the cluster it runs in, and 6 of 6 carry a severity from the five allowed levels.
- **SC-007 — A change is quick.** A person can change one limit and see the new limit in use within 2 minutes, by running one command and without reinstalling the monitoring system.
- **SC-008 — Setup is safe to repeat.** Running the Azure monitoring setup a second time succeeds. This story’s alert-rule step creates 0 new objects and changes 0 installed rules. Records that the rest of the existing monitoring setup keeps of its own rerun do not count as rule changes.
- **SC-009 — Part of the one-shot setup.** After the one-shot Azure setup finishes on a new cluster, 6 of 6 alerts are present on the alerts page, and the person ran 0 extra steps to get them.
- **SC-010 — Other setups are untouched.** The local (k3d) setup and the AWS setup have 0 behavior changes and install 0 of these alert rules. Shared setup files and documentation may change only to add and explain the Azure-only step. The existing Bookinfo rule is unchanged.
- **SC-011 — Faults and monitoring still work.** Starting and reverting each of the two faults still ends with its own "done" message, as before, and the repository's lint check passes with 0 errors. Before the rules are installed and after verification, shop measurements still update, an existing dashboard shows current shop data, and a newly recorded shop request opens as a trace showing its individual steps.
- **SC-012 — The limits are explained.** 3 of 3 tuned limits (shipping slow, ratings slow, server-error share) have their value and the reason for it written down.

## Assumptions

"Finding N" below points at the numbered findings in `research.md`, where the real terminal output is kept.

**What is already in place (checked on the live cluster)**

- The Azure cluster already runs the demo shop, the monitoring system and the metrics sources these alerts need. A restart of a stopped cluster brought everything back with no repair (Finding 1). A cluster that is stopped between sessions must be started before any check in this story.
- The monitoring system can load new alert rules without being changed or reinstalled (Finding 1).
- The monitoring system has no ready-made alert rules for the shop today. All six alerts are written from scratch (Finding 1).
- When a fault starts, its numbers reach the monitoring system within about 45 seconds (Finding 2). This is why a few minutes is enough in SC-001 and SC-002.

**What is not in this story**

- Nothing is sent anywhere. There is no tool yet that receives alerts, so they can only be seen on the alerts page. Sending them is the work of the next stories.
- The one-shot Azure setup does not start the load generator; it only prints how to start it. A person must start it before a fault, because without shop traffic the server-error and slow-request alerts have nothing to measure and will not fire.
- Rules are not written for the traffic demo (hotrod), for Grafana's own alerts, or for dashboards. The unused Bookinfo rule is only noted as a follow-up.

**Choices made, and why**

- **Shipping and ratings replace payment for slow requests.** Story #122 names payment. Findings 3 and 4 showed payment is slow and uneven with no fault, and it did not slow down during the slow-database fault. Shipping and ratings are the requests that fault slows, so the developer chose them on 2026-10-27. Anyone checking this spec against the story should treat this as agreed, not as a gap.
- **Only server errors count for the error alert.** Replies such as "not found" are not server errors. The shop already returns some of those with no fault (Finding 3), so counting them would make the healthy shop noisy.
- **One fault can raise alerts on more than one service.** When the cart is down, the website that depends on it also returns server errors, so the server-error alert shows for both (Finding 3). That is expected, not a mistake.
- **The starting limits for slow requests come from the slow-database story:** shipping over 2 seconds and ratings over 0.5 seconds. They are a starting point only (see the next item).
- **Which severity each alert gets** (from the five levels in FR-008) is decided in the plan, not here.

**Not yet known**

- **The final limits.** Findings 3 and 4 are single short samples. Shipping's normal slowest 5 percent is already about 1 second, and ratings' is about 0.14 seconds, but a 30-minute quiet run is still needed to confirm them. The values are chosen and written down during planning and checked in the live run (FR-012, SC-012).
- **The "wait before firing" time and the server-error share** are not chosen. They are set in the plan from the same measurements.
- **Whether the slow-database fault also raises the server-error alert** is not measured. The slow-database story says no request fails, and SC-005 relies on that. The live run decides it.

**Facts to carry, with no check of their own**

- The rules live inside the Azure cluster, so deleting the cluster removes them. Removing only the monitoring install would not, because the rules are separate from it. No requirement or check covers this; it is noted so nobody expects otherwise.

## Edge Cases

This list is closed when the spec is approved. Later review steps check the work against these cases and do not add new ones. "EC" stands for Edge Case. Each says what must happen.

- **EC-001 — No shop traffic.** With the load generator stopped, the server-error and slow-request alerts have nothing to measure and do not fire, even during a fault. A quiet alerts page then does not mean the rules are broken. The out-of-memory, restart and no-ready-copy alerts do not need traffic and still fire.
- **EC-002 — The cluster was stopped and has just started.** Right after a start, shop services take a few minutes to become ready. The 30-minute quiet run (SC-003) counts from the moment every shop service is ready. A start from a stopped cluster showed 0 restarts and no server errors in the last checks (Findings 2 and 3), so this is expected to be quiet, but it is not promised for the first minutes.
- **EC-003 — A fault is removed and the alert lingers.** Alerts measure the last few minutes, so one can stay on for several minutes after the fix before it clears. That is normal as long as it clears within the time in SC-004. The earlier Keep try-out saw about 8 minutes for the slowest one.
- **EC-004 — A pod is replaced during a fault.** The cart memory fault replaces the cart's pod with a new one, and the restart count belongs to each pod (Finding 2). The restart alert MUST still fire for the new pod, and MUST NOT stay on forever because of an old pod's count.
- **EC-005 — Very few requests.** If a service receives only a handful of requests, one failure is a huge share of them (rabbitmq showed 1 error in Finding 3). The server-error alert MUST NOT fire on a handful of requests. The same applies to the slow-request alerts for shipping and ratings: a few slow requests out of a few do not raise an alert.
- **EC-006 — Both faults at once.** If the cart memory fault and the slow-database fault run together, the alerts of both show, except the shipping slow-request alert. With the cart down, no requests reach shipping, so that alert has no data to fire on (it needs at least 30 requests in its window). This was accepted on 2026-10-28 (research Finding 9). SC-005 (each fault raises only its own alerts) is about one fault at a time.
- **EC-007 — A normal redeploy of the shop.** Replacing a shop service's pods on purpose leaves it without a ready copy for a short time. The wait before firing (FR-009) is meant to keep that quiet. This has not been tested; the plan confirms it.
- **EC-008 — Running the setup twice.** The second run succeeds, and this story’s alert-rule step creates nothing new and leaves the installed rules unchanged (FR-014, SC-008).

## Out of Scope

These are not part of this story. A reviewer who finds one of them missing has not found a gap.

- **Sending alerts anywhere.** Installing the tool that receives alerts, passing alerts to it, grouping the alerts of one fault into one incident, and posting to Slack are the next stories in the same epic (#123 onward). This story only makes alerts appear on the alerts page.
- **Alerts for payment.** A payment slow-request alert is deliberately dropped (see Assumptions and Story 2).
- **Other alert sources.** Rules for the traffic demo (hotrod), Grafana's own alerts, and dashboards are not part of this story.
- **Other kinds of alerts.** Only the six alerts in this spec are in scope. Alerts for things such as node health, disk space or CPU use are not.
- **The old Bookinfo rule.** It is in the settings shared with the local and AWS setups. It is left as it is (FR-016) and recorded as a follow-up story.
- **The local (k3d) and AWS setups.** Their behavior does not change, and they do not receive these alert rules. Shared files may receive only the Azure-only additions and explanations allowed by FR-013 and SC-010.
- **Changing the faults or the load generator.** The cart memory fault, the slow-database fault and the load generator are used as they are.
