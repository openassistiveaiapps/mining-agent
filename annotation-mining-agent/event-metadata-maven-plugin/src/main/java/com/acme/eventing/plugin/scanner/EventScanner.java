package com.acme.eventing.plugin.scanner;

import com.acme.eventing.plugin.model.EventMetadata;
import com.acme.eventing.plugin.model.TriggerDef;
import com.github.javaparser.*;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.Node;
import com.github.javaparser.ast.NodeList;
import com.github.javaparser.ast.body.*;
import com.github.javaparser.ast.expr.*;
import org.apache.maven.plugin.logging.Log;
import java.util.regex.Pattern;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.stream.Stream;

public class EventScanner {

    private final Log log;
    private final String annotationSimpleName;
    private final String annotationFqn;
    private final boolean failOnMissing;
    private final List<String> includes;
    private final List<String> excludes;

    public EventScanner(Log log,
                    String annotationSimpleName,
                    String annotationFqn,
                    boolean failOnMissing,
                    String[] includes,
                    String[] excludes) {

    this.log = log;
    this.annotationSimpleName = annotationSimpleName;
    this.annotationFqn = annotationFqn;
    this.failOnMissing = failOnMissing;

    // defaults
        this.includes = normalizePatterns(includes, List.of("**/*.java"));
        this.excludes = normalizePatterns(excludes, List.of());
    }

    private static List<String> normalizePatterns(String[] patterns, List<String> defaults) {
    if (patterns == null || patterns.length == 0) return defaults;
    List<String> out = new ArrayList<>();
    for (String p : patterns) {
        if (p != null && !p.isBlank()) out.add(p.trim());
    }
    return out.isEmpty() ? defaults : out;
    }

    public EventMetadata scan(Path sourceRoot) throws IOException {
        EventMetadata out = new EventMetadata();

        ParserConfiguration cfg = new ParserConfiguration()
            .setCharacterEncoding(StandardCharsets.UTF_8);

        JavaParser parser = new JavaParser(cfg);

        try (Stream<Path> paths = Files.walk(sourceRoot)) {
            paths.filter(Files::isRegularFile)
     .filter(p -> matches(sourceRoot, p))
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

    private final Map<String, PathMatcher> matcherCache = new HashMap<>();

    private boolean matches(Path sourceRoot, Path file) {
        Path relPath = sourceRoot.relativize(file);

        boolean included = includes.stream().anyMatch(glob -> matchGlob(glob, relPath));
        if (!included) return false;

        boolean excluded = excludes.stream().anyMatch(glob -> matchGlob(glob, relPath));
        return !excluded;
    }

    private boolean matchGlob(String glob, Path relPath) {
        // PathMatcher uses OS separators. On Mac/Linux it's already "/".
        // If someone passes patterns with "/", this still works on Mac.
        String normalized = glob.trim();

        PathMatcher pm = matcherCache.computeIfAbsent(normalized,
            g -> FileSystems.getDefault().getPathMatcher("glob:" + g)
        );

        return pm.matches(relPath);
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
            String msg = "Invalid @" + annotationSimpleName + " (missing topic/eventType) in " + file +
                        " target=" + target + " line=" + getLine(ann);

            if (failOnMissing) {
                throw new IllegalArgumentException(msg);
            } else {
                log.warn(msg);
                return null;
            }
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
