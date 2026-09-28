/**
 * Base class for the "one trigger per object" pattern. A trigger instantiates its
 * handler subclass and calls run(); this class dispatches to the matching lifecycle
 * hook and provides a static bypass mechanism so handlers can be disabled for the
 * remainder of a transaction (e.g. to break recursion or during data loads).
 */
public virtual class TriggerHandler {

    @TestVisible
    private static Set<String> bypassedHandlers = new Set<String>();

    private TriggerContext context;
    private Boolean isTriggerExecuting = false;

    public TriggerHandler() {
        this.isTriggerExecuting = Trigger.isExecuting;
        this.setTriggerContext();
    }

    public void run() {
        if (!this.isTriggerExecuting) {
            throw new TriggerHandlerException(
                getHandlerName() + '.run() can only be called from within a trigger context.'
            );
        }

        if (isBypassed(getHandlerName())) {
            return;
        }

        switch on this.context {
            when BEFORE_INSERT {
                this.beforeInsert();
            }
            when BEFORE_UPDATE {
                this.beforeUpdate();
            }
            when BEFORE_DELETE {
                this.beforeDelete();
            }
            when AFTER_INSERT {
                this.afterInsert();
            }
            when AFTER_UPDATE {
                this.afterUpdate();
            }
            when AFTER_DELETE {
                this.afterDelete();
            }
            when AFTER_UNDELETE {
                this.afterUndelete();
            }
        }
    }

    public static void bypass(String handlerName) {
        bypassedHandlers.add(handlerName);
    }

    public static void clearBypass(String handlerName) {
        bypassedHandlers.remove(handlerName);
    }

    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName);
    }

    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    // Resolved from the runtime type of `this`, so subclasses never need to override it.
    @TestVisible
    private String getHandlerName() {
        return String.valueOf(this).split(':')[0];
    }

    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}

    private void setTriggerContext() {
        if (!Trigger.isExecuting) {
            return;
        }

        if (Trigger.isBefore && Trigger.isInsert) {
            this.context = TriggerContext.BEFORE_INSERT;
        } else if (Trigger.isBefore && Trigger.isUpdate) {
            this.context = TriggerContext.BEFORE_UPDATE;
        } else if (Trigger.isBefore && Trigger.isDelete) {
            this.context = TriggerContext.BEFORE_DELETE;
        } else if (Trigger.isAfter && Trigger.isInsert) {
            this.context = TriggerContext.AFTER_INSERT;
        } else if (Trigger.isAfter && Trigger.isUpdate) {
            this.context = TriggerContext.AFTER_UPDATE;
        } else if (Trigger.isAfter && Trigger.isDelete) {
            this.context = TriggerContext.AFTER_DELETE;
        } else if (Trigger.isAfter && Trigger.isUndelete) {
            this.context = TriggerContext.AFTER_UNDELETE;
        }
    }

    private enum TriggerContext {
        BEFORE_INSERT, BEFORE_UPDATE, BEFORE_DELETE,
        AFTER_INSERT, AFTER_UPDATE, AFTER_DELETE, AFTER_UNDELETE
    }

    public class TriggerHandlerException extends Exception {}
}
