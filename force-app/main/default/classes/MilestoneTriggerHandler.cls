/**
 * One trigger per object: MilestoneTrigger delegates entirely to this handler,
 * which resolves the affected Project__c ids and hands them to
 * MilestoneRollupService for recalculation.
 */
public with sharing class MilestoneTriggerHandler extends TriggerHandler {

    protected override void afterInsert() {
        MilestoneRollupService.recalculateProjects(
            collectProjectIds((List<Milestone__c>) Trigger.new, null)
        );
    }

    protected override void afterUpdate() {
        MilestoneRollupService.recalculateProjects(
            collectProjectIds((List<Milestone__c>) Trigger.new, (Map<Id, Milestone__c>) Trigger.oldMap)
        );
    }

    protected override void afterDelete() {
        MilestoneRollupService.recalculateProjects(
            collectProjectIds((List<Milestone__c>) Trigger.old, null)
        );
    }

    protected override void afterUndelete() {
        MilestoneRollupService.recalculateProjects(
            collectProjectIds((List<Milestone__c>) Trigger.new, null)
        );
    }

    // Includes the previous parent when a milestone is reparented, so both the old
    // and the new Project__c get recalculated.
    private Set<Id> collectProjectIds(List<Milestone__c> milestones, Map<Id, Milestone__c> oldMilestonesById) {
        Set<Id> projectIds = new Set<Id>();

        for (Milestone__c milestone : milestones) {
            if (milestone.Project__c != null) {
                projectIds.add(milestone.Project__c);
            }

            if (oldMilestonesById != null) {
                Milestone__c oldMilestone = oldMilestonesById.get(milestone.Id);
                if (oldMilestone != null
                    && oldMilestone.Project__c != null
                    && oldMilestone.Project__c != milestone.Project__c) {
                    projectIds.add(oldMilestone.Project__c);
                }
            }
        }

        return projectIds;
    }
}
