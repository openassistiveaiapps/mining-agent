package com.acme.eventing.plugin.model;

public class TriggerDef {
    private String sourceFile;
    private int line;
    private String target;       // ClassName or ClassName#method
    private String topic;
    private String eventType;
    private int version;
    private String producer;
    private String description;

    public String getSourceFile() { return sourceFile; }
    public void setSourceFile(String sourceFile) { this.sourceFile = sourceFile; }

    public int getLine() { return line; }
    public void setLine(int line) { this.line = line; }

    public String getTarget() { return target; }
    public void setTarget(String target) { this.target = target; }

    public String getTopic() { return topic; }
    public void setTopic(String topic) { this.topic = topic; }

    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }

    public int getVersion() { return version; }
    public void setVersion(int version) { this.version = version; }

    public String getProducer() { return producer; }
    public void setProducer(String producer) { this.producer = producer; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
}
