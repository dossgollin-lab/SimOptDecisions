# Documentation

This directory contains the Quarto-based documentation for SimOptDecisions.jl.

## Building Locally

```bash
cd docs
julia --project -e 'using Pkg; Pkg.instantiate()'
quarto render
```

## Important: Use `engine: julia`

All `.qmd` files with Julia code blocks **must** use `engine: julia`, not a Jupyter kernel.

The `_quarto.yml` sets this globally, but individual files can override it. If you create a new `.qmd` file with Julia code, ensure the YAML frontmatter includes:

```yaml
---
title: "Your Title"
engine: julia
execute:
  exeflags: ["--project=.."]
---
```

### Why not IJulia/Jupyter?

- `engine: julia` uses `QuartoNotebookRunner.jl` which is simpler and more reliable in CI
- IJulia requires Conda/Jupyter setup which is fragile in GitHub Actions
- The Julia engine is faster and has better error messages

### Dependencies

The `docs/Project.toml` should include:
- `QuartoNotebookRunner` (required for `engine: julia`)
- Any packages used in the documentation examples

It should **not** include `IJulia`.
