# Specification Quality Checklist: Slow Database Fault for the Demo Shop on Azure

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-22
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

Checked 2026-10-22 against `spec.md` (152 lines):

- `grep -c "NEEDS CLARIFICATION" spec.md` printed `0`. The three questions raised while authoring (which database, status command, naming) were settled with the developer section by section.
- A search for implementation terms (database product name, `kubectl`, `helm`, mesh and monitoring tool names, file extensions, `make`, pod, namespace) found nothing in the spec.
- Each of the 14 functional requirements maps to an acceptance scenario or a success criterion: FR-001/002/004 to stories 1 and 2 and SC-001/004/010; FR-003 to SC-001/004; FR-005 to SC-002/003; FR-006 to SC-008; FR-007 to EC-006; FR-008/009 to story 3 and SC-007; FR-010 to SC-001/004/005; FR-011/014 to story 4 and SC-009; FR-012 to SC-011; FR-013 to SC-012.

Open points that are not spec defects, carried to planning (constitution principle VIII, live research):

- EC-002 records that it is not yet known whether the fault survives a shop re-deploy; the plan settles it on the live cluster. EC-003 was settled by clarification on 2026-10-22: the fault must survive a database restart (FR-003, SC-013).
- The 2-second and 10-second "slow" limits (success criteria) and the 60-second command limit (SC-006) were chosen from a baseline of 10 ratings requests and one shipping probe. They have not been tried against a slowed database or the dashboards.
- Whether other parts of the shop use the database is not confirmed beyond ratings and shipping.
- "Azure scenario 03" shares a number with the EKS zone-outage scenario 03; EC-009 and FR-011 require the guides to say which is which.
- "Feature meets measurable outcomes" is satisfied as defined; it cannot be shown until the feature is built.

Re-checked 2026-10-23 after the amendment (`spec.md`, 180 lines):

- `grep -c "NEEDS CLARIFICATION" spec.md` printed `0`.
- A search for implementation terms (`kubectl`, `helm`, `istio`, `grafana`, `prometheus`, `tempo`, `mysql`, `plugin`, `rewrit`, `make `, `pod`, `namespace`, `.yaml`, `.sh`) matched only the plain English "make" in "Make the database slow" (line 33) and "does not make" (line 101). No product, tool or file name.
- The spec now has 16 functional requirements and 15 success criteria. FR-016 (the new Azure-only slow-requests dashboard) maps to SC-015; FR-015 maps to SC-014. Ratings is back in scope and covered by FR-001, FR-002, FR-005, FR-008, FR-009 and SC-001, SC-002, SC-004.
