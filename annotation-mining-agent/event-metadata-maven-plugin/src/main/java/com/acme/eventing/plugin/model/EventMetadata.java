package com.acme.eventing.plugin.model;

import java.util.ArrayList;
import java.util.List;

public class EventMetadata {
    private String schemaVersion = "1";
    private List<TriggerDef> triggers = new ArrayList<>();

    public String getSchemaVersion() { return schemaVersion; }
    public void setSchemaVersion(String schemaVersion) { this.schemaVersion = schemaVersion; }

    public List<TriggerDef> getTriggers() { return triggers; }
    public void setTriggers(List<TriggerDef> triggers) { this.triggers = triggers; }
}
