# 📦 Annotation Mining Agent – Maven Plugin

## Overview

The **Annotation Mining Agent** is a custom Maven plugin that scans Java source code for specific eventing annotations and generates deterministic JSON metadata during build time.

This enables:

- Pre-build annotation validation
- Event contract extraction
- Pipeline-driven metadata generation
- Governance enforcement (fail builds when required metadata is missing)
- Cross-team event discovery

The plugin performs static analysis using JavaParser (AST-based scanning, not regex).

---

# 🧠 What Problem This Solves

In distributed systems, eventing annotations often:

- Define topics
- Define event types
- Define payload contracts
- Drive CI/CD behavior

However:

- These annotations are not centrally indexed.
- Teams may forget required fields.
- Pipelines cannot easily infer event impact.

This plugin:

✔ Extracts event metadata  
✔ Validates required fields  
✔ Supports strict (fail) or warn mode  
✔ Generates structured JSON for pipeline use  

---

# 🏗 Architecture

The project is structured as a multi-module Maven build:

```
event-metadata/
│
├── event-annotations/                # SOURCE-retained annotations
├── event-metadata-maven-plugin/      # Annotation scanner plugin
├── sample-app/                       # Demo module
└── pom.xml
```

---

# 🔍 How It Works

During Maven build (default phase: `generate-resources`):

1. Scans `src/main/java`
2. Parses Java files using JavaParser AST
3. Finds configured annotation (default: `@EventTrigger`)
4. Extracts:
   - topic
   - eventType
   - version
   - producer
   - description
5. Resolves simple constants
6. Applies include/exclude filters
7. Validates required fields
8. Outputs JSON to:

```
target/event-metadata.json
```

---

# 📄 Example Annotation

```java
@EventTrigger(
    topic = "orders.v1",
    eventType = "OrderCreated",
    version = 1,
    producer = "order-service"
)
public class OrderService {
}
```

Generated JSON:

```json
{
  "schemaVersion": "1",
  "triggers": [
    {
      "sourceFile": "src/main/java/com/acme/app/OrderService.java",
      "line": 6,
      "target": "OrderService",
      "topic": "orders.v1",
      "eventType": "OrderCreated",
      "version": 1,
      "producer": "order-service",
      "description": ""
    }
  ]
}
```

---

# 🚀 How To Use (Other Teams)

## 1️⃣ Add Plugin to Your Module

Add to your module’s `pom.xml`:

```xml
<plugin>
  <groupId>com.yourco.build</groupId>
  <artifactId>event-metadata-maven-plugin</artifactId>
  <version>1.0.0</version>

  <executions>
    <execution>
      <goals>
        <goal>generate</goal>
      </goals>
    </execution>
  </executions>

  <configuration>
    <annotationName>EventTrigger</annotationName>
    <annotationFqn>com.yourco.eventing.EventTrigger</annotationFqn>
  </configuration>
</plugin>
```

---

## 2️⃣ Run It

Automatically during:

```
mvn clean package
```

Or manually:

```
mvn event-metadata:generate
```

---

# ⚙ Configuration Options

## Fail On Missing (Strict Mode)

If required fields (topic/eventType) are missing:

### Default
Warn and skip invalid triggers.

### Enable Strict Mode
Fail the build:

```
mvn -DeventMetadata.failOnMissing=true event-metadata:generate
```

---

## Include / Exclude Filters

Filter which Java files are scanned.

### Include Patterns (glob)
Default:
```
**/*.java
```

### Example

```
mvn event-metadata:generate \
  -DeventMetadata.includes="**/*.java" \
  -DeventMetadata.excludes="**/generated/**,**/*Test.java"
```

Common Excludes:

- `**/generated/**`
- `**/*Test.java`
- `**/*IT.java`
- `**/target/**`

---

# 📦 Publishing The Plugin

## Option 1: Publish to Internal Maven Repository

Add `distributionManagement` to plugin POM:

```xml
<distributionManagement>
  <repository>
    <id>internal-releases</id>
    <url>https://your-maven-repo/releases</url>
  </repository>
  <snapshotRepository>
    <id>internal-snapshots</id>
    <url>https://your-maven-repo/snapshots</url>
  </snapshotRepository>
</distributionManagement>
```

Deploy:

```
mvn -pl event-metadata-maven-plugin -am clean deploy
```

---

## Option 2: Local Install (Temporary)

```
mvn -pl event-metadata-maven-plugin -am install
```

---

# 🔒 Deterministic Design

This plugin intentionally:

✔ Uses AST parsing (not regex)  
✔ Avoids runtime reflection  
✔ Resolves simple static final String constants  
✔ Supports repeatable annotations  
✔ Produces stable sorted output (clean CI diffs)  

No AI inference is used in metadata generation.

---

# 🧪 Validation Strategy

Supports:

| Mode | Behavior |
|------|----------|
| Warn | Logs invalid annotations |
| Strict | Fails build on invalid annotations |

You can enforce governance across org by enabling strict mode in CI.

---

# 🧭 CI/CD Integration Example

Example GitHub Actions step:

```yaml
- name: Generate event metadata
  run: mvn -B -DeventMetadata.failOnMissing=true event-metadata:generate
```

Artifact upload:

```yaml
- name: Upload metadata
  uses: actions/upload-artifact@v3
  with:
    name: event-metadata
    path: target/event-metadata.json
```

---

# 📈 Future Enhancements

Planned / Possible Extensions:

- Detect changed files via Git diff
- Only scan impacted modules
- Add `failOnEmpty` (fail if no triggers found)
- Extract `.class` payload types
- Support enums
- Central event registry integration
- Optional AI enrichment layer
- Multi-module aggregation output

---

# 🛠 Local Development

Build entire project:

```
mvn clean install
```

Check sample output:

```
cat sample-app/target/event-metadata.json
```

---

# 👩‍💻 Contributing

When modifying scanner logic:

- Ensure output remains deterministic
- Maintain stable ordering
- Avoid introducing runtime-only resolution
- Keep parsing compile-time safe

---

# 🎯 Summary

This plugin enables:

✔ Event discovery  
✔ Pre-build validation  
✔ CI governance enforcement  
✔ Metadata-driven pipelines  
✔ Cross-team event transparency  

It converts code annotations into machine-readable metadata at build time.