package com.acme.eventing.plugin;

import com.acme.eventing.plugin.model.EventMetadata;
import com.acme.eventing.plugin.scanner.EventScanner;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.*;

import java.io.File;
import java.nio.file.Path;

@Mojo(
    name = "generate",
    defaultPhase = LifecyclePhase.GENERATE_RESOURCES,
    threadSafe = true
)
public class GenerateEventMetadataMojo extends AbstractMojo {

    /**
     * Root directory to scan. Defaults to ${project.basedir}/src/main/java
     */
    @Parameter(property = "eventMetadata.sourceDir",
               defaultValue = "${project.basedir}/src/main/java")
    private File sourceDir;

    /**
     * Output JSON file.
     */
    @Parameter(property = "eventMetadata.outputFile",
               defaultValue = "${project.build.directory}/event-metadata.json")
    private File outputFile;

    /**
     * Annotation simple name to look for.
     * Example: EventTrigger
     */
    @Parameter(property = "eventMetadata.annotationName",
               defaultValue = "EventTrigger")
    private String annotationName;

    /**
     * Optional: also match by fully-qualified name (if you want stricter matching).
     * Example: com.acme.eventing.EventTrigger
     */
    @Parameter(property = "eventMetadata.annotationFqn",
               defaultValue = "com.acme.eventing.EventTrigger")
    private String annotationFqn;

    /**
     * If true: fail the build when an @EventTrigger is present but missing required fields
     * (topic/eventType), or cannot be resolved deterministically.
     * If false: warn and skip those invalid triggers.
     */
    @Parameter(property = "eventMetadata.failOnMissing", defaultValue = "false")
    private boolean failOnMissing;

    /**
     * Glob patterns (relative to sourceDir) to include.
    */
    @Parameter(property = "eventMetadata.includes")
    private String[] includes;

    /**
     * Glob patterns (relative to sourceDir) to exclude.
    */
    @Parameter(property = "eventMetadata.excludes")
    private String[] excludes;

    @Override
    public void execute() throws MojoExecutionException {
        try {
            Path src = sourceDir.toPath();
            if (!sourceDir.exists()) {
                getLog().info("Source dir does not exist, skipping: " + src);
                return;
            }

            getLog().info("Scanning Java sources: " + src);
            EventScanner scanner = new EventScanner(
                getLog(),
                annotationName,
                annotationFqn,
                failOnMissing,
                includes,
                excludes
            );

            EventMetadata metadata = scanner.scan(src);

            File parent = outputFile.getParentFile();
            if (parent != null) parent.mkdirs();

            ObjectMapper om = new ObjectMapper()
                .enable(SerializationFeature.INDENT_OUTPUT);

            om.writeValue(outputFile, metadata);

            getLog().info("Wrote event metadata: " + outputFile.getAbsolutePath());
            getLog().info("Found triggers: " + metadata.getTriggers().size());
        } catch (Exception e) {
            throw new MojoExecutionException("Failed to generate event metadata", e);
        }
    }
}
