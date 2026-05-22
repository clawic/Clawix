#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const manifestPath = path.join(repoRoot, "docs", "surface-route-registry.manifest.json");
const outputPath = path.join(repoRoot, "macos", "Sources", "Clawix", "SurfaceRouteRegistry.generated.swift");
const argv = new Set(process.argv.slice(2));

const validCriticalities = new Set(["core", "protected", "extensionSurface"]);
const validBindings = new Set(["uuid", "string", "optionalString", "optionalDate"]);

function readManifest(filePath = manifestPath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function swiftString(value) {
  return JSON.stringify(String(value)).replaceAll("\\/", "/");
}

function swiftOptionalString(value) {
  return value == null ? "nil" : `normalizedRouteTarget(${swiftString(value)})`;
}

function bindingPattern(route) {
  const bindings = route.bindings ?? [];
  if (bindings.length === 0) return `.${route.case}`;
  return `.${route.case}(${bindings.map((binding) => `let ${binding.name}`).join(", ")})`;
}

function tokenExpression(token) {
  if (token.endsWith(".uuidString")) {
    return `${token.slice(0, -".uuidString".length)}.uuidString`;
  }
  if (token.endsWith(".hashValueOrZero")) {
    return `${token.slice(0, -".hashValueOrZero".length)}?.hashValue ?? 0`;
  }
  if (token.endsWith(".timeIntervalSince1970OrZero")) {
    return `${token.slice(0, -".timeIntervalSince1970OrZero".length)}?.timeIntervalSince1970 ?? 0`;
  }
  return token;
}

function swiftTemplate(template) {
  const parts = [];
  let index = 0;
  const pattern = /\{([^}]+)\}/gu;
  for (let match = pattern.exec(template); match; match = pattern.exec(template)) {
    parts.push(template.slice(index, match.index));
    parts.push({ expression: tokenExpression(match[1]) });
    index = match.index + match[0].length;
  }
  parts.push(template.slice(index));
  let source = "\"";
  for (const part of parts) {
    if (typeof part === "string") {
      source += part.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"");
    } else {
      source += `\\(${part.expression})`;
    }
  }
  source += "\"";
  return source;
}

function swiftOptionalTemplate(value) {
  return value == null ? "nil" : `normalizedRouteTarget(${swiftTemplate(value)})`;
}

function timeoutExpression(route) {
  if (route.timeoutSeconds != null) return String(route.timeoutSeconds);
  if (route.criticality === "core") return "nil";
  if (route.criticality === "protected") return "8";
  return "5";
}

function requiresIndependentDegradation(route) {
  if (route.requiresIndependentDegradation != null) return route.requiresIndependentDegradation;
  return route.criticality !== "core";
}

function readinessMode(route) {
  return route.readinessMode ?? "immediateAfterFirstRender";
}

function supportsVariantDefault(route) {
  if (route.supportsVariantDefault != null) return route.supportsVariantDefault;
  return route.routeTarget != null;
}

function dependenciesExpression(route) {
  const dependencies = route.dependencies ?? [];
  if (dependencies.length === 0) return "[]";
  return `[${dependencies.map((dependency) => `.${dependency}`).join(", ")}]`;
}

function validateManifest(manifest) {
  const failures = [];
  if (manifest.version !== 1) failures.push("version must be 1");
  if (!Array.isArray(manifest.modules) || manifest.modules.length === 0) failures.push("modules must be a non-empty array");
  if (!Array.isArray(manifest.dependencies)) failures.push("dependencies must be an array");
  if (!Array.isArray(manifest.readinessModes)) failures.push("readinessModes must be an array");
  if (!Array.isArray(manifest.routes) || manifest.routes.length === 0) failures.push("routes must be a non-empty array");

  const modules = new Set(manifest.modules ?? []);
  const dependencies = new Set(manifest.dependencies ?? []);
  const readinessModes = new Set(manifest.readinessModes ?? []);
  const seenCases = new Set();
  for (const route of manifest.routes ?? []) {
    if (!route.case) failures.push("route is missing case");
    if (seenCases.has(route.case)) failures.push(`duplicate route case: ${route.case}`);
    seenCases.add(route.case);
    if (!route.id) failures.push(`${route.case}: missing id`);
    if (!modules.has(route.module)) failures.push(`${route.case}: unknown module ${route.module}`);
    if (!validCriticalities.has(route.criticality)) failures.push(`${route.case}: unknown criticality ${route.criticality}`);
    if (!readinessModes.has(readinessMode(route))) failures.push(`${route.case}: unknown readinessMode ${readinessMode(route)}`);
    for (const dependency of route.dependencies ?? []) {
      if (!dependencies.has(dependency)) failures.push(`${route.case}: unknown dependency ${dependency}`);
    }
    for (const binding of route.bindings ?? []) {
      if (!binding.name || !validBindings.has(binding.kind)) failures.push(`${route.case}: invalid binding ${JSON.stringify(binding)}`);
    }
  }

  if (!readinessModes.has("immediateAfterFirstRender")) failures.push("readinessModes must include immediateAfterFirstRender");
  if (!readinessModes.has("childReported")) failures.push("readinessModes must include childReported");
  if (failures.length > 0) throw new Error(failures.join("\n"));
}

function caseBlock(route) {
  const id = swiftTemplate(route.id);
  const target = swiftOptionalTemplate(route.routeTarget);
  const support = supportsVariantDefault(route) ? "true" : "false";
  const degradation = requiresIndependentDegradation(route) ? "true" : "false";
  return `        case ${bindingPattern(route)}:
            return SurfaceRouteMetadata(
                routeCase: ${swiftString(route.case)},
                id: ${id},
                module: .${route.module},
                criticality: .${route.criticality},
                routeTarget: ${target},
                supportsVariantDefault: ${support},
                timeoutSeconds: ${timeoutExpression(route)},
                requiresIndependentDegradation: ${degradation},
                readinessMode: .${readinessMode(route)},
                dependencies: ${dependenciesExpression(route)}
            )`;
}

function renderSwift(manifest) {
  validateManifest(manifest);
  const modules = manifest.modules.map((module) => `    case ${module}`).join("\n");
  const routeCases = manifest.routes.map((route) => swiftString(route.case)).join(", ");
  const moduleKinds = manifest.modules.map(swiftString).join(", ");
  const dependencyKinds = manifest.dependencies.map(swiftString).join(", ");
  const readinessKinds = manifest.readinessModes.map(swiftString).join(", ");
  const childReportedCases = manifest.routes
    .filter((route) => readinessMode(route) === "childReported")
    .map((route) => swiftString(route.case))
    .join(", ");
  return `// Generated by scripts/generate-surface-route-registry.mjs from docs/surface-route-registry.manifest.json.
// Do not edit by hand.

import Foundation

enum SurfaceRouteModule: String, Equatable, Hashable, CaseIterable {
${modules}
}

struct SurfaceRouteMetadata: Equatable {
    var routeCase: String
    var id: String
    var module: SurfaceRouteModule
    var criticality: SurfaceRouteCriticality
    var routeTarget: String?
    var supportsVariantDefault: Bool
    var timeoutSeconds: TimeInterval?
    var requiresIndependentDegradation: Bool
    var readinessMode: SurfaceRouteReadinessMode
    var dependencies: Set<SurfaceRouteDependency>

    var descriptor: SurfaceRouteDescriptor {
        SurfaceRouteDescriptor(
            id: id,
            criticality: criticality,
            routeTarget: routeTarget,
            supportsVariantDefault: supportsVariantDefault,
            timeoutSeconds: timeoutSeconds,
            requiresIndependentDegradation: requiresIndependentDegradation,
            dependencies: dependencies
        )
    }
}

enum SurfaceRouteMetadataCatalog {
    static let manifestVersion = ${manifest.version}
    static let manifestRouteCases: Set<String> = [${routeCases}]
    static let manifestModuleKinds: Set<String> = [${moduleKinds}]
    static let manifestDependencyKinds: Set<String> = [${dependencyKinds}]
    static let manifestReadinessModeKinds: Set<String> = [${readinessKinds}]
    static let manifestDirectChildReportedRouteCases: Set<String> = [${childReportedCases}]

    static func metadata(for route: SidebarRoute) -> SurfaceRouteMetadata {
        switch route {
${manifest.routes.map(caseBlock).join("\n")}
        }
    }

    private static func normalizedRouteTarget(_ routeTarget: String) -> String {
        routeTarget.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension SidebarRoute {
    var surfaceRouteMetadata: SurfaceRouteMetadata {
        SurfaceRouteMetadataCatalog.metadata(for: self)
    }
}
`;
}

function runSelfTest() {
  const valid = {
    version: 1,
    modules: ["core", "apps"],
    dependencies: ["customApps"],
    readinessModes: ["immediateAfterFirstRender", "childReported"],
    routes: [
      { case: "home", id: "home", module: "core", criticality: "core", dependencies: [] },
      { case: "app", bindings: [{ name: "id", kind: "uuid" }], id: "app:{id.uuidString}", module: "apps", criticality: "extensionSurface", readinessMode: "childReported", dependencies: ["customApps"] },
    ],
  };
  const swift = renderSwift(valid);
  if (!swift.includes("case .app(let id):")) throw new Error("self-test failed to render binding pattern");
  if (!swift.includes("\"app:\\(id.uuidString)\"")) throw new Error("self-test failed to render id interpolation");

  const invalid = structuredClone(valid);
  invalid.routes.push({ case: "home", id: "other", module: "core", criticality: "core", dependencies: [] });
  try {
    validateManifest(invalid);
  } catch {
    console.log("surface route registry generator self-test passed");
    return;
  }
  throw new Error("self-test failed to reject duplicate route cases");
}

if (argv.has("--self-test")) {
  runSelfTest();
  process.exit(0);
}

const manifest = readManifest();
const swift = renderSwift(manifest);
if (argv.has("--check")) {
  const existing = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8") : "";
  if (existing !== swift) {
    console.error(`${path.relative(repoRoot, outputPath)} is out of date. Run scripts/generate-surface-route-registry.mjs.`);
    process.exit(1);
  }
  console.log(JSON.stringify({
    ok: true,
    manifest: path.relative(repoRoot, manifestPath),
    generatedSwift: path.relative(repoRoot, outputPath),
    routes: manifest.routes.length,
  }, null, 2));
  process.exit(0);
}

fs.writeFileSync(outputPath, swift);
console.log(`Generated ${path.relative(repoRoot, outputPath)} from ${path.relative(repoRoot, manifestPath)}`);
