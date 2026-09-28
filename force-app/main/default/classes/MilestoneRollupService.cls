/**
 * Recalculates the Milestone__c aggregates stored on Project__c (total budget,
 * completed milestone count, and derived completion status). Called from
 * MilestoneTriggerHandler for every DML type on Milestone__c.
 */
public inherited sharing class MilestoneRollupService {

    // Recursion guard: blocks re-entrant calls within the same call stack. Scoped to a
    // single invocation (reset in the finally block), so it never blocks a later,
    // independent DML statement within the same transaction.
    @TestVisible
    private static Boolean isRecalculating = false;

    public static void recalculateProjects(Set<Id> projectIds) {
        if (isRecalculating || projectIds == null || projectIds.isEmpty()) {
            return;
        }

        isRecalculating = true;
        try {
            Map<Id, MilestoneAggregate> aggregatesByProjectId = queryAggregates(projectIds);

            List<Project__c> projectsToUpdate = new List<Project__c>();
            for (Id projectId : projectIds) {
                MilestoneAggregate aggregate = aggregatesByProjectId.get(projectId);
                if (aggregate == null) {
                    aggregate = new MilestoneAggregate();
                }
                projectsToUpdate.add(new Project__c(
                    Id = projectId,
                    Total_Milestone_Budget__c = aggregate.totalBudget,
                    Completed_Milestones_Count__c = aggregate.completedCount,
                    Status__c = aggregate.deriveStatus()
                ));
            }

            updateProjectsSecurely(projectsToUpdate);
        } finally {
            isRecalculating = false;
        }
    }

    private static Map<Id, MilestoneAggregate> queryAggregates(Set<Id> projectIds) {
        Map<Id, MilestoneAggregate> aggregatesByProjectId = new Map<Id, MilestoneAggregate>();

        List<Milestone__c> milestones = [
            SELECT Project__c, Amount__c, Status__c
            FROM Milestone__c
            WHERE Project__c IN :projectIds
            WITH USER_MODE
        ];

        for (Milestone__c milestone : milestones) {
            MilestoneAggregate aggregate = aggregatesByProjectId.get(milestone.Project__c);
            if (aggregate == null) {
                aggregate = new MilestoneAggregate();
                aggregatesByProjectId.put(milestone.Project__c, aggregate);
            }
            aggregate.addMilestone(milestone);
        }

        return aggregatesByProjectId;
    }

    private static void updateProjectsSecurely(List<Project__c> projects) {
        if (projects.isEmpty()) {
            return;
        }

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, projects);
        List<Project__c> accessibleProjects = decision.getRecords();
        if (!accessibleProjects.isEmpty()) {
            update accessibleProjects;
        }
    }

    private class MilestoneAggregate {
        private Integer totalCount = 0;
        private Integer completedCount = 0;
        private Decimal totalBudget = 0;

        private void addMilestone(Milestone__c milestone) {
            this.totalCount++;
            this.totalBudget += (milestone.Amount__c != null ? milestone.Amount__c : 0);
            if (milestone.Status__c == 'Completed') {
                this.completedCount++;
            }
        }

        private String deriveStatus() {
            if (this.totalCount == 0) {
                return 'Not Started';
            }
            return this.completedCount == this.totalCount ? 'Completed' : 'In Progress';
        }
    }
}
