#!/usr/bin/env bash
set -euo pipefail

# Creates a multi-module Maven project:
# - event-annotations (your SOURCE-retained pre-build annotations)
# - event-metadata-maven-plugin (scans Java files + emits JSON)
# - sample-app (demo usage)
#
# Usage:
#   ./create-event-metadata-project.sh [TARGET_DIR]
#
# Example:
#   ./create-event-metadata-project.sh event-metadata
#   cd event-metadata
#   mvn -q clean install
#   cat sample-app/target/event-metadata.json

ROOT_DIR="${1:-event-metadata}"

mkdir -p "$ROOT_DIR"
cd "$ROOT_DIR"

# -------------------------
# Root pom.xml
# -------------------------
cat > pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.acme</groupId>
  <artifactId>event-metadata</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>

  <modules>
    <module>event-annotations</module>
    <module>event-metadata-maven-plugin</module>
    <module>sample-app</module>
  </modules>

  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
</project>
XML

# -------------------------
# event-annotations module
# -------------------------
mkdir -p event-annotations/src/main/java/com/acme/eventing

cat > event-annotations/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>com.acme</groupId>
    <artifactId>event-metadata</artifactId>
    <version>1.0.0</version>
  </parent>

  <artifactId>event-annotations</artifactId>
  <packaging>jar</packaging>
</project>
XML

cat > event-annotations/src/main/java/com/acme/eventing/EventTrigger.java <<'JAVA'
package com.acme.eventing;

import java.lang.annotation.*;

@Retention(RetentionPolicy.SOURCE)
@Target({ElementType.TYPE, ElementType.METHOD})
@Repeatable(EventTriggers.class)
public @interface EventTrigger {
    String topic();
    String eventType();
    int version() default 1;

    // Optional fields (nice for metadata and reporting)
    String producer() default "";
    String description() default "";
}
JAVA

cat > event-annotations/src/main/java/com/acme/eventing/EventTriggers.java <<'JAVA'
package com.acme.eventing;

import java.lang.annotation.*;

@Retention(RetentionPolicy.SOURCE)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface EventTriggers {
    EventTrigger[] value();
}
JAVA

# -------------------------
# Maven plugin module
# -------------------------
mkdir -p event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin
mkdir -p event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin/model
mkdir -p event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin/scanner

cat > event-metadata-maven-plugin/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>com.acme</groupId>
    <artifactId>event-metadata</artifactId>
    <version>1.0.0</version>
  </parent>

  <artifactId>event-metadata-maven-plugin</artifactId>
  <packaging>maven-plugin</packaging>

  <dependencies>
    <!-- AST parsing -->
    <dependency>
      <groupId>com.github.javaparser</groupId>
      <artifactId>javaparser-symbol-solver-core</artifactId>
      <version>3.26.2</version>
    </dependency>

    <!-- JSON output -->
    <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.17.2</version>
    </dependency>

    <!-- Maven plugin API -->
    <dependency>
      <groupId>org.apache.maven</groupId>
      <artifactId>maven-plugin-api</artifactId>
      <version>3.9.9</version>
    </dependency>
    <dependency>
      <groupId>org.apache.maven.plugin-tools</groupId>
      <artifactId>maven-plugin-annotations</artifactId>
      <version>3.11.0</version>
      <scope>provided</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugin-tools</groupId>
        <artifactId>maven-plugin-plugin</artifactId>
        <version>3.11.0</version>
        <configuration>
          <goalPrefix>event-metadata</goalPrefix>
        </configuration>
        <executions>
          <execution>
            <id>default-descriptor</id>
            <goals>
              <goal>descriptor</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
XML

cat > event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin/GenerateEventMetadataMojo.java <<'JAVA'
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

    @Override
    public void execute() throws MojoExecutionException {
        try {
            Path src = sourceDir.toPath();
            if (!sourceDir.exists()) {
                getLog().info("Source dir does not exist, skipping: " + src);
                return;
            }

            getLog().info("Scanning Java sources: " + src);
            EventScanner scanner = new EventScanner(getLog(), annotationName, annotationFqn);

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
JAVA

cat > event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin/model/EventMetadata.java <<'JAVA'
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
JAVA

cat > event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin/model/TriggerDef.java <<'JAVA'
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
JAVA

cat > event-metadata-maven-plugin/src/main/java/com/acme/eventing/plugin/scanner/EventScanner.java <<'JAVA'
package com.acme.eventing.plugin.scanner;

import com.acme.eventing.plugin.model.EventMetadata;
import com.acme.eventing.plugin.model.TriggerDef;
import com.github.javaparser.*;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.Node;
import com.github.javaparser.ast.body.*;
import com.github.javaparser.ast.expr.*;
import org.apache.maven.plugin.logging.Log;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.stream.Stream;

public class EventScanner {

    private final Log log;
    private final String annotationSimpleName;
    private final String annotationFqn;

    public EventScanner(Log log, String annotationSimpleName, String annotationFqn) {
        this.log = log;
        this.annotationSimpleName = annotationSimpleName;
        this.annotationFqn = annotationFqn;
    }

    public EventMetadata scan(Path sourceRoot) throws IOException {
        EventMetadata out = new EventMetadata();

        ParserConfiguration cfg = new ParserConfiguration()
            .setCharacterEncoding(StandardCharsets.UTF_8);

        JavaParser parser = new JavaParser(cfg);

        try (Stream<Path> paths = Files.walk(sourceRoot)) {
            paths.filter(p -> p.toString().endsWith(".java"))
                 .forEach(p -> parseFile(parser, sourceRoot, p, out));
        }

        // Stable ordering helps diffs in CI
        out.getTriggers().sort(Comparator
            .comparing(TriggerDef::getSourceFile)
            .thenComparingInt(TriggerDef::getLine)
            .thenComparing(TriggerDef::getTarget)
        );

        return out;
    }

    private void parseFile(JavaParser parser, Path sourceRoot, Path file, EventMetadata out) {
        try {
            ParseResult<CompilationUnit> result = parser.parse(file);
            if (!result.isSuccessful() || result.getResult().isEmpty()) {
                log.warn("Failed to parse: " + file);
                return;
            }

            CompilationUnit cu = result.getResult().get();

            // Support simple constants inside the same file:
            // static final String X = "..."
            Map<String, String> stringConsts = collectStaticFinalStrings(cu);

            for (TypeDeclaration<?> type : cu.getTypes()) {
                if (type instanceof ClassOrInterfaceDeclaration c) {
                    handleType(sourceRoot, file, c, stringConsts, out);
                }
            }
        } catch (Exception e) {
            log.warn("Error scanning file: " + file + " - " + e.getMessage());
        }
    }

    private void handleType(Path sourceRoot, Path file, ClassOrInterfaceDeclaration c,
                            Map<String, String> stringConsts,
                            EventMetadata out) {

        String className = c.getNameAsString();

        // Class-level annotations
        extractTriggersFromAnnotations(sourceRoot, file, className, c.getAnnotations(), stringConsts, out);

        // Method-level annotations
        for (MethodDeclaration m : c.getMethods()) {
            String target = className + "#" + m.getNameAsString();
            extractTriggersFromAnnotations(sourceRoot, file, target, m.getAnnotations(), stringConsts, out);
        }
    }

    private void extractTriggersFromAnnotations(Path sourceRoot, Path file, String target,
                                                NodeList<AnnotationExpr> annotations,
                                                Map<String, String> stringConsts,
                                                EventMetadata out) {

        for (AnnotationExpr ann : annotations) {
            // Direct annotation: @EventTrigger(...)
            if (isTargetAnnotation(ann)) {
                TriggerDef def = parseEventTrigger(ann, sourceRoot, file, target, stringConsts);
                if (def != null) out.getTriggers().add(def);
            }

            // Container annotation: @EventTriggers({@EventTrigger(...), ...})
            if (ann.getNameAsString().equals("EventTriggers") && ann.isNormalAnnotationExpr()) {
                NormalAnnotationExpr na = ann.asNormalAnnotationExpr();
                for (MemberValuePair pair : na.getPairs()) {
                    if (pair.getNameAsString().equals("value") && pair.getValue().isArrayInitializerExpr()) {
                        ArrayInitializerExpr arr = pair.getValue().asArrayInitializerExpr();
                        for (Expression e : arr.getValues()) {
                            if (e.isAnnotationExpr()) {
                                AnnotationExpr inner = e.asAnnotationExpr();
                                if (isTargetAnnotation(inner)) {
                                    TriggerDef def = parseEventTrigger(inner, sourceRoot, file, target, stringConsts);
                                    if (def != null) out.getTriggers().add(def);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private boolean isTargetAnnotation(AnnotationExpr ann) {
        String name = ann.getNameAsString();

        // Common case: @EventTrigger
        if (name.equals(annotationSimpleName)) return true;

        // If the source uses fully-qualified annotation: @com.acme.eventing.EventTrigger
        if (name.contains(".") && name.equals(annotationFqn)) return true;

        return false;
    }

    private TriggerDef parseEventTrigger(AnnotationExpr ann,
                                         Path sourceRoot,
                                         Path file,
                                         String target,
                                         Map<String, String> stringConsts) {

        if (!ann.isNormalAnnotationExpr()) {
            // We expect named members like topic/eventType
            return null;
        }

        NormalAnnotationExpr na = ann.asNormalAnnotationExpr();
        Map<String, Expression> args = new HashMap<>();
        for (MemberValuePair pair : na.getPairs()) {
            args.put(pair.getNameAsString(), pair.getValue());
        }

        String topic = resolveString(args.get("topic"), stringConsts);
        String eventType = resolveString(args.get("eventType"), stringConsts);

        // defaults
        int version = resolveInt(args.getOrDefault("version", new IntegerLiteralExpr("1")));
        String producer = resolveString(args.getOrDefault("producer", new StringLiteralExpr("")), stringConsts);
        String description = resolveString(args.getOrDefault("description", new StringLiteralExpr("")), stringConsts);

        // required fields check
        if (topic == null || topic.isBlank() || eventType == null || eventType.isBlank()) {
            log.warn("Skipping trigger with missing required fields topic/eventType in " + file);
            return null;
        }

        TriggerDef def = new TriggerDef();
        def.setTarget(target);
        def.setTopic(topic);
        def.setEventType(eventType);
        def.setVersion(version);
        def.setProducer(producer);
        def.setDescription(description);

        def.setSourceFile(sourceRoot.relativize(file).toString().replace('\\', '/'));
        def.setLine(getLine(ann));
        return def;
    }

    private int getLine(Node node) {
        return node.getRange().map(r -> r.begin.line).orElse(-1);
    }

    private Map<String, String> collectStaticFinalStrings(CompilationUnit cu) {
        Map<String, String> out = new HashMap<>();

        for (TypeDeclaration<?> type : cu.getTypes()) {
            for (FieldDeclaration f : type.getFields()) {
                if (!f.isStatic() || !f.isFinal()) continue;
                if (!f.getElementType().isClassOrInterfaceType()) continue;
                if (!f.getElementType().asString().equals("String")) continue;

                for (VariableDeclarator v : f.getVariables()) {
                    if (v.getInitializer().isPresent()) {
                        Expression init = v.getInitializer().get();
                        if (init.isStringLiteralExpr()) {
                            out.put(v.getNameAsString(), init.asStringLiteralExpr().asString());
                        }
                    }
                }
            }
        }
        return out;
    }

    private String resolveString(Expression e, Map<String, String> stringConsts) {
        if (e == null) return null;

        if (e.isStringLiteralExpr()) return e.asStringLiteralExpr().asString();

        // topic = SOME_CONST (static final String SOME_CONST = "...")
        if (e.isNameExpr()) {
            String name = e.asNameExpr().getNameAsString();
            return stringConsts.get(name);
        }

        // Simple concatenation: "a" + "b" or CONST + "b"
        if (e.isBinaryExpr()) {
            BinaryExpr b = e.asBinaryExpr();
            if (b.getOperator() == BinaryExpr.Operator.PLUS) {
                String left = resolveString(b.getLeft(), stringConsts);
                String right = resolveString(b.getRight(), stringConsts);
                if (left != null && right != null) return left + right;
            }
        }

        // Anything more complex -> keep deterministic, return null
        return null;
    }

    private int resolveInt(Expression e) {
        if (e == null) return 0;
        if (e.isIntegerLiteralExpr()) {
            try { return Integer.parseInt(e.asIntegerLiteralExpr().getValue()); }
            catch (NumberFormatException ex) { return 0; }
        }
        return 0;
    }
}
JAVA

# -------------------------
# sample-app module
# -------------------------
mkdir -p sample-app/src/main/java/com/acme/app

cat > sample-app/pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>com.acme</groupId>
    <artifactId>event-metadata</artifactId>
    <version>1.0.0</version>
  </parent>

  <artifactId>sample-app</artifactId>
  <packaging>jar</packaging>

  <dependencies>
    <dependency>
      <groupId>com.acme</groupId>
      <artifactId>event-annotations</artifactId>
      <version>${project.version}</version>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>com.acme</groupId>
        <artifactId>event-metadata-maven-plugin</artifactId>
        <version>${project.version}</version>
        <executions>
          <execution>
            <goals>
              <goal>generate</goal>
            </goals>
          </execution>
        </executions>
        <configuration>
          <outputFile>${project.build.directory}/event-metadata.json</outputFile>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
XML

cat > sample-app/src/main/java/com/acme/app/OrderEvents.java <<'JAVA'
package com.acme.app;

public final class OrderEvents {
    private OrderEvents() {}

    public static final String TOPIC = "orders.v1";
}
JAVA

cat > sample-app/src/main/java/com/acme/app/OrderService.java <<'JAVA'
package com.acme.app;

import com.acme.eventing.EventTrigger;

@EventTrigger(topic = OrderEvents.TOPIC, eventType = "OrderCreated", version = 1, producer = "sample-app")
public class OrderService {

    @EventTrigger(topic = "orders.v1", eventType = "OrderCancelled", version = 2, description = "Emitted on cancel")
    public void cancelOrder(String orderId) {
        // ...
    }
}
JAVA

# -------------------------
# Done
# -------------------------
cat <<'TXT'

✅ Project created.

Next steps:
  cd event-metadata
  mvn -q clean install
  cat sample-app/target/event-metadata.json

To run plugin directly on sample-app:
  cd event-metadata/sample-app
  mvn -q -DskipTests event-metadata:generate
  cat target/event-metadata.json

TXT