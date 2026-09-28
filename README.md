# Enterprise Trigger Architecture & Rollup Engine

A Salesforce backend project demonstrating a hand-rolled, production-style trigger
architecture — no declarative rollup tools (e.g. DLRS), just Apex.

Two custom objects, `Project__c` (parent) and `Milestone__c` (child), are linked by a
standard lookup. Every insert, update, delete, and undelete on `Milestone__c`
recalculates three aggregates on its parent `Project__c`: total budget, completed
milestone count, and a derived completion status. Because the relationship is a plain
lookup (not master-detail), none of this can be done with a native Roll-Up Summary
field — the whole point of the project is the Apex trigger architecture, not the data
model shortcut.

## Architecture

- **One Trigger Per Object** — a single `MilestoneTrigger` handles all seven trigger
  contexts and delegates immediately to `MilestoneTriggerHandler`.
- **Trigger Handler Framework** (`TriggerHandler.cls`) — a small reusable base class
  that dispatches to `beforeInsert` / `afterUpdate` / etc. virtual hooks and exposes a
  static bypass mechanism (`TriggerHandler.bypass('HandlerName')`) so any handler can
  be disabled for the rest of a transaction.
- **Rollup logic** (`MilestoneRollupService.cls`) — the only place that queries
  `Milestone__c` and writes back to `Project__c`. It aggregates in memory (single
  SOQL query per invocation, bulk-safe) and derives:
  - `Total_Milestone_Budget__c` = sum of `Amount__c`
  - `Completed_Milestones_Count__c` = count of milestones with `Status__c = 'Completed'`
  - `Status__c` = `Not Started` / `In Progress` / `Completed`, derived from the two above
- **Recursion protection** — `MilestoneRollupService` guards re-entrant calls with a
  static `Boolean` flag scoped to a single invocation (set in `recalculateProjects`,
  cleared in a `finally` block), so a single recalculation can never trigger itself
  again mid-flight, while still allowing independent DML statements later in the same
  transaction to recalculate normally.
- **Security** — the rollup query uses `WITH USER_MODE` (enforces FLS + sharing on
  read), and the write path runs every record through
  `Security.stripInaccessible(AccessType.UPDATABLE, ...)` before the `update` DML.

## Data model

| Object | Field | Type | Notes |
|---|---|---|---|
| `Project__c` | `Status__c` | Picklist | Not Started / In Progress / Completed — Apex-managed |
| `Project__c` | `Total_Milestone_Budget__c` | Currency(16,2) | Apex-managed |
| `Project__c` | `Completed_Milestones_Count__c` | Number(18,0) | Apex-managed |
| `Milestone__c` | `Project__c` | Lookup(Project__c) | Required, delete-restricted |
| `Milestone__c` | `Status__c` | Picklist | Not Started / In Progress / Completed |
| `Milestone__c` | `Amount__c` | Currency(16,2) | Contributes to the parent budget |

## Apex classes

| Class | Purpose |
|---|---|
| `TriggerHandler` | Generic base class for the trigger-handler pattern |
| `MilestoneTriggerHandler` | Resolves affected `Project__c` ids (including reparenting) and calls the service |
| `MilestoneRollupService` | Aggregation, recursion guard, secure read/write |
| `MilestoneTrigger` | The single trigger on `Milestone__c` |
| `TestDataFactory` | Bulk-friendly test data builders |
| `MilestoneRollupServiceTest` | Full test suite (bulk 200, insert/update/delete/undelete, reparenting, bypass, negative and security scenarios) |

## Testing

`MilestoneRollupServiceTest` covers:

- Bulk insert of 200 milestones in one DML statement
- Update, delete, undelete, and reparenting (moving a milestone between projects)
- Negative scenarios: empty/null input, deleting every milestone resets a project to zero
- The bypass mechanism and `clearAllBypasses`
- The recursion guard being a genuine no-op when re-entered
- A restricted user (no FLS on the custom fields) being blocked by `WITH USER_MODE`

Run it with:

```bash
sf apex run test --target-org <alias> --class-names MilestoneRollupServiceTest --code-coverage --wait 10
```

Current coverage: 96% org-wide (100% on the trigger and handler, 98% on the service).

## Deploying

```bash
sf project deploy start --target-org <alias> --source-dir force-app
```

The repo also ships a permission set, `Enterprise_Trigger_Rollup_Access`, granting
CRUD + FLS on both objects — assign it to any user (including the deploying user) that
needs to exercise the rollup, since Metadata API deploys do not grant field-level
security automatically:

```bash
sf org assign permset --target-org <alias> --name Enterprise_Trigger_Rollup_Access
```
