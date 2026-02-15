# AGENTS.md — OpenMRS 3.0 Reference Application

## Overview

This is the **OpenMRS 3.0 Reference Application distribution** — an assembly project that combines core OpenMRS modules (Java) and frontend SPA modules. **It contains no application source code**; instead, it assembles pre-built modules via Maven.

## Build & Test Commands

```bash
# Full distribution (Java + frontend)
mvn -P distro,frontend clean install

# Java-only distribution
mvn -P distro clean install

# Frontend-only distribution
mvn -P frontend clean install

# Skip tests
mvn -P distro,frontend clean install -DskipTests

# Run a single test (not applicable — this project has no tests)
# Tests reside in individual OpenMRS module repositories
```

## Code Style Guidelines

### Configuration Files (JSON, YAML, Properties)

- **JSON**: Use 2-space indentation, double quotes, trailing commas allowed  
- **YAML**: Use 2-space indentation, avoid tabs  
- **Maven properties** (`pom.xml`): Use kebab-case for property names (e.g., `fhir2.version`)  
- **SPA configs** (`spa-build-config.json`, `spa-assemble-config.json`): Follow schema documented in OpenMRS 3.0 SPA docs

### Maven (`pom.xml`)

- Use modules for explicit dependency ordering  
- Define module versions as properties in root `<properties>`  
- Use `-P distro` for Java assemblies, `-P frontend` for SPA assemblies  
- Never hardcode versions — always use properties

### Java (in assembled modules)

- Follow OpenMRS Java coding standards (not enforced here — resides in module repos)  
- Use SLF4J for logging: `private static final Logger log = LoggerFactory.getLogger(MyClass.class);`  
- Exceptions: Log at appropriate level (`warn`, `error`) before rethrowing

### Frontend (SPA modules)

- This project consumes pre-built SPA modules — no local React/TypeScript code  
- SPA modules must follow OpenMRS 3.0 SPA conventions (module ID, entry point, manifest)

## Linting & Formatting

- **No linting tools** are configured in this assembly project  
- Format configuration files with standard tools:  
  - JSON: `prettier --write "*.json"`  
  - YAML: `prettier --write "*.yaml"`  
  - XML: `mvn com.github.ekryd.sortpom:sortpom-maven-plugin:sort` (if configured in module)

## Project Structure

```
openmrs-distro-referenceapplication/
├── pom.xml                 # Root aggregator
├── distro/
│   ├── pom.xml             # Java module versions
│   └── assembly.xml        # Java distribution layout
├── frontend/
│   ├── pom.xml             # Frontend assembly config
│   ├── assembly.xml        # SPA assembly layout
│   ├── spa-build-config.json
│   └── spa-assemble-config.json
└── AGENTS.md               # This file
```

## Important Notes for Agentic Tools

1. **No source code exists here** — this project only assembles modules  
2. **No tests exist** — testing is done in individual module repositories  
3. To modify Java/TS source: edit the respective OpenMRS module repo, not this distro  
4. To update versions: edit properties in `distro/pom.xml` and/or `pom.xml`  
5. Always run `mvn -P distro,frontend clean install` before committing changes
