@isTest
public class TestDataFactory {

    public static Project__c buildProject(String name) {
        return new Project__c(Name = name);
    }

    public static List<Project__c> buildProjects(Integer count, String namePrefix) {
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 0; i < count; i++) {
            projects.add(buildProject(namePrefix + i));
        }
        return projects;
    }

    public static Project__c insertProject(String name) {
        Project__c project = buildProject(name);
        insert project;
        return project;
    }

    public static Milestone__c buildMilestone(Id projectId, Decimal amount, String status) {
        return new Milestone__c(
            Name = 'Milestone',
            Project__c = projectId,
            Amount__c = amount,
            Status__c = status
        );
    }

    public static List<Milestone__c> buildMilestones(Id projectId, Integer count, Decimal amountEach, String status) {
        List<Milestone__c> milestones = new List<Milestone__c>();
        for (Integer i = 0; i < count; i++) {
            milestones.add(buildMilestone(projectId, amountEach, status));
        }
        return milestones;
    }
}
