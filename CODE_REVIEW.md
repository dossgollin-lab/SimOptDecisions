# Code Review: SimOptDecisions.jl

A comprehensive analysis of code quality, documentation alignment, and framework design for the SimOptDecisions.jl package.

---

## Executive Summary

SimOptDecisions.jl is a well-architected Julia framework for simulation-optimization under deep uncertainty. The codebase demonstrates good separation of concerns, clean abstractions, and thoughtful API design. However, this review identifies several opportunities for improvement across documentation consistency, code clarity, and framework simplicity.

**Key Findings:**
- 3 High-priority issues (documentation/code misalignment, API confusion)
- 5 Medium-priority issues (code quality, maintainability)
- 7 Lower-priority issues (clarity, minor inconsistencies)

---

## 1. Documentation/Code Misalignments (High Priority)

### 1.1 Vocabulary Inconsistency: "Config" vs "Params"

**Location:** Throughout codebase

**Issue:** CLAUDE.md and docs/index.qmd establish "Config" as the correct vocabulary term for `AbstractConfig`, but the example files and some docstrings use "params" inconsistently:

| Source | Term Used |
|--------|-----------|
| CLAUDE.md | Config (AbstractConfig) |
| docs/index.qmd | Config, Fixed Parameters |
| investment_growth.qmd | `InvestmentParams` |
| house_elevation.qmd | `HouseElevationParams` |
| validation.jl docstring | `validate(params::AbstractConfig)` |

**Impact:** Users reading the documentation may be confused about whether to name their types `MyConfig` or `MyParams`.

**Recommendation:** Standardize on "Config" naming in examples:
- Rename `InvestmentParams` → `InvestmentConfig`
- Rename `HouseElevationParams` → `HouseElevationConfig`
- Update docstring in validation.jl: `validate(config::AbstractConfig)`

### 1.2 Redundant `simulate` Override in Examples

**Location:** `docs/examples/investment_growth.qmd:144-152`, `docs/examples/house_elevation.qmd:349-357`

**Issue:** Both examples explicitly define `simulate()` that just calls `TimeStepping.run_simulation()`:

```julia
function SimOptDecisions.simulate(
    params::InvestmentParams,
    sow::InvestmentSOW,
    policy::InvestmentPolicy,
    rng::AbstractRNG,
)
    SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)
end
```

However, the documentation and code both state this is automatic:
- simulation.jl:17-25 already provides this default
- docs/index.qmd:54 says "By default, `simulate` automatically calls `TimeStepping.run_simulation`"

**Impact:** Users may think they need this boilerplate when they don't.

**Recommendation:** Remove these explicit `simulate` definitions from examples and add a note explaining the automatic connection.

### 1.3 STYLE.md Project Structure Omits Files

**Location:** `STYLE.md:126-146`

**Issue:** The project structure section is missing several files that exist:
- `src/utils.jl` - not listed
- `src/plotting.jl` - not listed
- `test/test_types.jl`, `test/test_recorders.jl`, etc. - not listed

**Recommendation:** Update STYLE.md to reflect actual project structure.

---

## 2. API Design Issues (High Priority)

### 2.1 Confusing `finalize` Function Overloading

**Location:** `src/recorders.jl:53`, `src/timestepping.jl:88-91`

**Issue:** The `finalize` function is used for two completely different purposes:
1. Converting `TraceRecorderBuilder` → `SimulationTrace` (recorders.jl)
2. Aggregating step records into outcome (timestepping.jl callback)

This causes:
- Potential confusion for users implementing callbacks
- Import collision handling in test/runtests.jl line 12: `import SimOptDecisions: finalize, step`

**Recommendation:** Rename the recorder conversion function to `build_trace()` or `to_trace()`:
```julia
trace = build_trace(builder)  # instead of finalize(builder)
```

### 2.2 Unexported `step` Function Referenced in Tests

**Location:** `test/runtests.jl:12`

**Issue:** The test file imports `step` but there's no `step` function in the codebase. This appears to be a vestige of an earlier design that used `step` instead of `run_timestep`.

**Recommendation:** Remove `step` from the import statement.

---

## 3. Code Quality Issues (Medium Priority)

### 3.1 Type Instability in `_extract_objectives`

**Location:** `src/optimization.jl:160-176`

**Issue:** Uses `push!` to build `Float64[]` array instead of pre-allocation:

```julia
function _extract_objectives(metrics::NamedTuple, objectives::Vector{Objective})
    values = Float64[]
    for obj in objectives
        ...
        push!(values, obj.direction == Maximize ? -val : val)
    end
    return values
end
```

**Recommendation:** Pre-allocate for better performance:
```julia
function _extract_objectives(metrics::NamedTuple, objectives::Vector{Objective})
    values = Vector{Float64}(undef, length(objectives))
    for (i, obj) in enumerate(objectives)
        ...
        values[i] = obj.direction == Maximize ? -val : val
    end
    return values
end
```

### 3.2 Inconsistent Use of Parametric Types in Core Structs

**Location:** Various source files

**Issue:** STYLE.md mandates parametric types (`T<:AbstractFloat`) but several core types use concrete `Float64`:

| Struct | Issue |
|--------|-------|
| `FractionBatch` | `fraction::Float64` |
| `OptimizationResult` | `best_params::Vector{Float64}`, `pareto_*::Vector{Vector{Float64}}` |
| `MetaheuristicsBackend` | `options::Dict{Symbol,Any}` |

**Impact:** While these are less critical than user-facing types, it reduces consistency.

**Recommendation:** At minimum, add a comment explaining why these use concrete types (optimization data always uses Float64).

### 3.3 `_validate_policy_interface` Error Handling

**Location:** `src/validation.jl:12-24`

**Issue:** The error catching uses string matching which is fragile:
```julia
if e isa ErrorException && contains(string(e), "Implement")
```

**Recommendation:** Check for `ArgumentError` thrown by `interface_not_implemented` instead:
```julia
if e isa ArgumentError
    throw(ArgumentError(...))
end
```

### 3.4 Hardcoded Version String

**Location:** `src/persistence.jl:102, 138`

**Issue:** Version is hardcoded as `"0.1.0"` in checkpoint/experiment save functions:
```julia
version="0.1.0"
```

**Recommendation:** Either:
1. Import version from Project.toml
2. Define a constant `const CHECKPOINT_VERSION = "0.1.0"`
3. Document that this is the checkpoint format version (not package version)

---

## 4. Maintainability Issues (Medium Priority)

### 4.1 Test Code Duplication

**Location:** `test/test_simulation.jl`, `test/test_timestepping.jl`, `test/test_optimization.jl`

**Issue:** Nearly identical test helper types are defined multiple times:
- `TSCounterState`, `TSCounterParams`, etc. defined in multiple testsets
- `EvalCounterPolicy` duplicates `OptCounterPolicy`

**Recommendation:** Create a shared `test/test_helpers.jl` with common test types.

### 4.2 Missing Docstrings for Key Internal Functions

**Location:** Throughout codebase

**Issue:** Several important internal functions lack docstrings:
- `_select_batch()` (optimization.jl:107-122)
- `_apply_constraints()` (ext/SimOptMetaheuristicsExt.jl:84)
- `_get_algorithm()` (ext/SimOptMetaheuristicsExt.jl:30)

**Recommendation:** Add brief docstrings even for internal functions, per STYLE.md guidelines.

### 4.3 Tables.jl Interface Could Use Helper

**Location:** `src/recorders.jl:79-101`

**Issue:** The `Tables.getcolumn` implementation has repetitive if-else chains:

```julia
function Tables.getcolumn(t::SimulationTrace, nm::Symbol)
    if nm === :state
        return t.states
    elseif nm === :step_record
        return t.step_records
    elseif nm === :time
        return t.times
    else
        throw(ArgumentError(...))
    end
end
```

**Recommendation:** Use `getfield` with property mapping:
```julia
const TRACE_COLUMNS = Dict(:state => :states, :step_record => :step_records, :time => :times)

function Tables.getcolumn(t::SimulationTrace, nm::Symbol)
    haskey(TRACE_COLUMNS, nm) || throw(ArgumentError(...))
    return getfield(t, TRACE_COLUMNS[nm])
end
```

---

## 5. Framework Design Issues for Didactic Clarity

### 5.1 `get_action` is Optional but Prominent in Docs

**Location:** `docs/index.qmd:88-112`

**Issue:** The `get_action` function is given significant documentation space, but:
1. It's never called by the framework itself
2. Users must manually call it inside `run_timestep`
3. Examples show both calling and not calling it

This creates confusion about whether it's required or optional.

**Current examples:**
- investment_growth.qmd: Calls `get_action` in `run_timestep`
- house_elevation.qmd: Calls `get_action` in `run_timestep`
- Test code: Sometimes defines it, sometimes doesn't

**Recommendation:** Either:
1. Have `run_simulation` automatically call `get_action` before `run_timestep`
2. Clearly document it as an **optional pattern** for organizing policy logic
3. Show examples both with and without it

### 5.2 StepRecord vs Output Terminology Confusion

**Location:** `docs/index.qmd:144`, `src/timestepping.jl:82`

**Issue:** The docs use "StepRecord" but code uses "step_record", "output", and "step_records" interchangeably:

| Location | Term |
|----------|------|
| CLAUDE.md | StepRecord |
| docs/index.qmd | StepRecord, step_record |
| timestepping.jl | step_record (in run_timestep), output (in run_simulation loop) |
| recorders.jl | step_records (in SimulationTrace) |

**Recommendation:** Standardize on one term throughout. "StepRecord" as the concept, `step_record` as the variable/field name.

### 5.3 SOW Sampling Not Part of Framework

**Location:** Examples only

**Issue:** SOW sampling/generation is a critical part of simulation-optimization but isn't addressed by the framework at all. Users must implement:
- `sample_sow(rng)` functions
- Latin Hypercube Sampling
- Prior distribution specification

**Recommendation:** Consider adding:
1. An `AbstractSOWSampler` interface
2. Helper utilities for common sampling patterns
3. At minimum, document this as an intentional design choice

### 5.4 Metric Calculator Signature Not Validated

**Location:** `src/optimization.jl:69`

**Issue:** The `metric_calculator::Function` is stored but never validated. Bad signatures fail at runtime with unclear errors.

**Recommendation:** Add validation in `OptimizationProblem` constructor:
```julia
# Validate metric_calculator with a test call
test_outcome = (placeholder=0.0,)  # Minimal outcome
try
    metrics = metric_calculator([test_outcome])
    if !(metrics isa NamedTuple)
        throw(ArgumentError("metric_calculator must return a NamedTuple"))
    end
catch e
    throw(ArgumentError("metric_calculator failed: $e"))
end
```

---

## 6. Minor Issues and Polish

### 6.1 Inconsistent Import Styles

**Location:** Extension files

**Issue:** Extensions use different import styles:
```julia
# SimOptMetaheuristicsExt.jl
import SimOptDecisions: optimize_backend, ...

# SimOptMakieExt.jl
import SimOptDecisions: plot_trace, ...
```

Both are correct, but `using ... : func` is more idiomatic for single functions.

### 6.2 Unused `to_scalars` Default Implementation

**Location:** `src/plotting.jl:15`

**Issue:** `to_scalars` has a default that throws, but it's not used anywhere in the Makie extension. The `plot_trace` function expects `step_records` to be NamedTuples directly.

**Recommendation:** Either implement state plotting that uses `to_scalars`, or remove it.

### 6.3 `TimeSeriesParameter` Conversion Behavior

**Location:** `src/timestepping.jl:60`

**Issue:** The fallback constructor converts to `Float64`:
```julia
TimeSeriesParameter(data) = TimeSeriesParameter(collect(Float64, data))
```

This silently converts `Int` arrays, potentially surprising users.

**Recommendation:** Add a warning or use `AbstractFloat`:
```julia
function TimeSeriesParameter(data)
    T = promote_type(eltype(data), Float64)
    TimeSeriesParameter(collect(T, data))
end
```

### 6.4 Missing `Base.length` for `TimeSeriesParameter` in Exports

**Location:** `src/SimOptDecisions.jl`

**Issue:** `length(ts::TimeSeriesParameter)` is defined but not exported or documented as part of the interface.

### 6.5 Quarto Execute Flags Reference Julia 1.12

**Location:** `docs/examples/*.qmd`

**Issue:** Both example files use:
```yaml
execute:
  exeflags: ["+1.12", "--threads=auto"]
```

This may fail for users on different Julia versions.

**Recommendation:** Use `+lts` or remove version pinning.

### 6.6 House Elevation Example Uses Statistics Without Import

**Location:** `docs/examples/house_elevation.qmd:592`

**Issue:** The file imports `Statistics: mean, quantile` at line 592, but the metric uses `mean()` without this import being available at that code location due to Quarto cell ordering.

**Recommendation:** Move the import to the setup cell.

### 6.7 Potential Issue with RNG Seeding in Optimization

**Location:** `ext/SimOptMetaheuristicsExt.jl:212`

**Issue:** The fitness function creates RNG from parameter hash:
```julia
rng = Random.Xoshiro(hash(x))
```

This is deterministic per parameter vector but may cause issues:
1. Hash collisions could give same results for different parameters
2. Small parameter changes may produce drastically different RNG sequences

**Recommendation:** Document this behavior or use a more robust seeding strategy.

---

## 7. Positive Observations

Despite the issues identified above, this codebase demonstrates many excellent practices:

1. **Clean separation of concerns** - Types, simulation, optimization, and persistence are well-isolated
2. **Thoughtful error messages** - `interface_not_implemented` provides clear guidance
3. **Type stability where it matters** - `NoRecorder` enables zero-allocation hot loops
4. **Flexible time axes** - Works with integers, floats, or Dates
5. **Well-structured tests** - Good coverage of core functionality
6. **Extension pattern** - Clean integration with Metaheuristics.jl and Makie.jl
7. **Tables.jl integration** - SimulationTrace works with DataFrames ecosystem

---

## Recommendations Summary

### Immediate (Before Release)

1. Fix vocabulary: Rename `*Params` → `*Config` in examples
2. Remove redundant `simulate()` definitions from examples
3. Fix or remove unused `step` import in tests

### Short-term

4. Rename `finalize(::TraceRecorderBuilder)` to `build_trace()`
5. Pre-allocate in `_extract_objectives`
6. Create shared test helpers to reduce duplication
7. Update STYLE.md project structure

### Medium-term

8. Clarify `get_action` as optional pattern
9. Standardize StepRecord terminology
10. Consider SOW sampling utilities
11. Add metric_calculator validation

---

## Conclusion

SimOptDecisions.jl is a solid foundation for simulation-optimization research. The identified issues are primarily about consistency and clarity rather than correctness. Addressing the high-priority documentation misalignments would significantly improve the onboarding experience for new users. The framework's core design is sound and supports the stated goal of creating "simple, didactic, reusable code."
