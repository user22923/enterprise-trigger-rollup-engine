@isTest
private class MilestoneRollupServiceTest {

    @isTest
    static void testBulkInsertRecalculatesAggregates() {
        Project__c project = TestDataFactory.insertProject('Bulk Insert Project');
        List<Milestone__c> milestones = TestDataFactory.buildMilestones(project.Id, 150, 100, 'Completed');
        milestones.addAll(TestDataFactory.buildMilestones(project.Id, 50, 100, 'Not Started'));

        Test.startTest();
        insert milestones;
        Test.stopTest();

        Project__c result = [
            SELECT Total_Milestone_Budget__c, Completed_Milestones_Count__c, Status__c
            FROM Project__c
            WHERE Id = :project.Id
        ];
        Assert.areEqual(20000, result.Total_Milestone_Budget__c, 'Budget should sum all 200 milestone amounts.');
        Assert.areEqual(150, result.Completed_Milestones_Count__c, 'Completed count should only include Completed milestones.');
        Assert.areEqual('In Progress', result.Status__c, 'Project should be In Progress when only some milestones are complete.');
    }

    @isTest
    static void testAllMilestonesCompletedMarksProjectCompleted() {
        Project__c project = TestDataFactory.insertProject('Fully Completed Project');
        insert TestDataFactory.buildMilestones(project.Id, 5, 200, 'Completed');

        Project__c result = [SELECT Status__c FROM Project__c WHERE Id = :project.Id];
        Assert.areEqual('Completed', result.Status__c, 'Project should be Completed once every milestone is Completed.');
    }

    @isTest
    static void testUpdateRecalculatesAggregates() {
        Project__c project = TestDataFactory.insertProject('Update Project');
        Milestone__c milestone = TestDataFactory.buildMilestone(project.Id, 500, 'Not Started');
        insert milestone;

        milestone.Status__c = 'Completed';
        milestone.Amount__c = 750;

        Test.startTest();
        update milestone;
        Test.stopTest();

        Project__c result = [
            SELECT Total_Milestone_Budget__c, Completed_Milestones_Count__c, Status__c
            FROM Project__c
            WHERE Id = :project.Id
        ];
        Assert.areEqual(750, result.Total_Milestone_Budget__c, 'Budget should reflect the updated amount.');
        Assert.areEqual(1, result.Completed_Milestones_Count__c, 'Completed count should reflect the updated status.');
        Assert.areEqual('Completed', result.Status__c, 'Single completed milestone means the project is fully completed.');
    }

    @isTest
    static void testReparentingMilestoneUpdatesBothProjects() {
        Project__c sourceProject = TestDataFactory.insertProject('Source Project');
        Project__c targetProject = TestDataFactory.insertProject('Target Project');
        Milestone__c milestone = TestDataFactory.buildMilestone(sourceProject.Id, 1000, 'Completed');
        insert milestone;

        milestone.Project__c = targetProject.Id;

        Test.startTest();
        update milestone;
        Test.stopTest();

        Project__c refreshedSource = [SELECT Total_Milestone_Budget__c, Status__c FROM Project__c WHERE Id = :sourceProject.Id];
        Project__c refreshedTarget = [SELECT Total_Milestone_Budget__c, Status__c FROM Project__c WHERE Id = :targetProject.Id];

        Assert.areEqual(0, refreshedSource.Total_Milestone_Budget__c, 'Source project should lose the reparented milestone budget.');
        Assert.areEqual('Not Started', refreshedSource.Status__c, 'Source project has no remaining milestones.');
        Assert.areEqual(1000, refreshedTarget.Total_Milestone_Budget__c, 'Target project should gain the reparented milestone budget.');
        Assert.areEqual('Completed', refreshedTarget.Status__c, 'Target project should reflect the moved milestone status.');
    }

    @isTest
    static void testDeleteRecalculatesAggregates() {
        Project__c project = TestDataFactory.insertProject('Delete Project');
        List<Milestone__c> milestones = TestDataFactory.buildMilestones(project.Id, 4, 100, 'Completed');
        insert milestones;

        Test.startTest();
        delete milestones[0];
        Test.stopTest();

        Project__c result = [
            SELECT Total_Milestone_Budget__c, Completed_Milestones_Count__c
            FROM Project__c
            WHERE Id = :project.Id
        ];
        Assert.areEqual(300, result.Total_Milestone_Budget__c, 'Budget should drop by the deleted milestone amount.');
        Assert.areEqual(3, result.Completed_Milestones_Count__c, 'Completed count should drop after deletion.');
    }

    @isTest
    static void testDeletingAllMilestonesResetsProjectToZero() {
        Project__c project = TestDataFactory.insertProject('Empty Project');
        List<Milestone__c> milestones = TestDataFactory.buildMilestones(project.Id, 3, 100, 'Completed');
        insert milestones;

        Test.startTest();
        delete milestones;
        Test.stopTest();

        Project__c result = [
            SELECT Total_Milestone_Budget__c, Completed_Milestones_Count__c, Status__c
            FROM Project__c
            WHERE Id = :project.Id
        ];
        Assert.areEqual(0, result.Total_Milestone_Budget__c, 'Budget should reset to zero with no milestones left.');
        Assert.areEqual(0, result.Completed_Milestones_Count__c, 'Completed count should reset to zero with no milestones left.');
        Assert.areEqual('Not Started', result.Status__c, 'A project with no milestones is Not Started.');
    }

    @isTest
    static void testUndeleteRestoresAggregates() {
        Project__c project = TestDataFactory.insertProject('Undelete Project');
        Milestone__c milestone = TestDataFactory.buildMilestone(project.Id, 900, 'Completed');
        insert milestone;
        delete milestone;

        Test.startTest();
        undelete milestone;
        Test.stopTest();

        Project__c result = [
            SELECT Total_Milestone_Budget__c, Completed_Milestones_Count__c, Status__c
            FROM Project__c
            WHERE Id = :project.Id
        ];
        Assert.areEqual(900, result.Total_Milestone_Budget__c, 'Budget should be restored after undelete.');
        Assert.areEqual(1, result.Completed_Milestones_Count__c, 'Completed count should be restored after undelete.');
        Assert.areEqual('Completed', result.Status__c, 'Status should be restored after undelete.');
    }

    @isTest
    static void testBypassSkipsRecalculation() {
        Project__c project = TestDataFactory.insertProject('Bypass Project');

        Test.startTest();
        TriggerHandler.bypass('MilestoneTriggerHandler');
        insert TestDataFactory.buildMilestone(project.Id, 5000, 'Completed');
        TriggerHandler.clearBypass('MilestoneTriggerHandler');
        Test.stopTest();

        Project__c result = [SELECT Total_Milestone_Budget__c, Status__c FROM Project__c WHERE Id = :project.Id];
        Assert.areEqual(0, result.Total_Milestone_Budget__c, 'Bypassed handler should not recalculate the parent.');
        Assert.areEqual('Not Started', result.Status__c, 'Bypassed handler should leave Status__c at its picklist default.');
    }

    @isTest
    static void testRecalculateProjectsIgnoresEmptyOrNullInput() {
        Test.startTest();
        MilestoneRollupService.recalculateProjects(null);
        MilestoneRollupService.recalculateProjects(new Set<Id>());
        Test.stopTest();
        // No exception means the guard clauses handled both cases correctly.
    }

    @isTest
    static void testDirectServiceCallDoesNotRecurseWhenAlreadyRecalculating() {
        Project__c project = TestDataFactory.insertProject('Recursion Guard Project');
        insert TestDataFactory.buildMilestone(project.Id, 100, 'Completed');

        MilestoneRollupService.isRecalculating = true;
        Test.startTest();
        MilestoneRollupService.recalculateProjects(new Set<Id>{ project.Id });
        Test.stopTest();
        MilestoneRollupService.isRecalculating = false;

        Project__c result = [SELECT Total_Milestone_Budget__c FROM Project__c WHERE Id = :project.Id];
        Assert.areEqual(100, result.Total_Milestone_Budget__c, 'Re-entrant call while the guard is set should be a no-op.');
    }

    @isTest
    static void testRunOutsideTriggerContextThrows() {
        Boolean exceptionThrown = false;
        try {
            new MilestoneTriggerHandler().run();
        } catch (TriggerHandler.TriggerHandlerException the) {
            exceptionThrown = true;
        }
        Assert.isTrue(exceptionThrown, 'run() must reject calls made outside of a trigger context.');
    }

    @isTest
    static void testClearAllBypassesReenablesHandler() {
        TriggerHandler.bypass('MilestoneTriggerHandler');
        TriggerHandler.clearAllBypasses();
        Assert.isFalse(
            TriggerHandler.isBypassed('MilestoneTriggerHandler'),
            'clearAllBypasses should remove every bypass, including MilestoneTriggerHandler.'
        );

        Project__c project = TestDataFactory.insertProject('Cleared Bypass Project');
        insert TestDataFactory.buildMilestone(project.Id, 250, 'Completed');

        Project__c result = [SELECT Total_Milestone_Budget__c FROM Project__c WHERE Id = :project.Id];
        Assert.areEqual(250, result.Total_Milestone_Budget__c, 'Rollup should run normally once bypasses are cleared.');
    }

    @isTest
    static void testRestrictedUserIsBlockedByFieldLevelSecurity() {
        Profile restrictedProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User restrictedUser = new User(
            ProfileId = restrictedProfile.Id,
            LastName = 'Restricted',
            FirstName = 'Test',
            Email = 'restricted.user@example.test',
            Username = 'restricted.user.' + DateTime.now().getTime() + '@example.test.invalid',
            Alias = 'restr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert restrictedUser;

        Project__c project = TestDataFactory.insertProject('Security Test Project');
        insert TestDataFactory.buildMilestone(project.Id, 100, 'Completed');

        Boolean accessWasDenied = false;
        System.runAs(restrictedUser) {
            try {
                MilestoneRollupService.recalculateProjects(new Set<Id>{ project.Id });
            } catch (System.NoAccessException nae) {
                accessWasDenied = true;
            } catch (System.QueryException qe) {
                accessWasDenied = true;
            }
        }

        Assert.isTrue(
            accessWasDenied,
            'A user without object/field permissions on Project__c or Milestone__c must be blocked by WITH USER_MODE.'
        );
    }
}
