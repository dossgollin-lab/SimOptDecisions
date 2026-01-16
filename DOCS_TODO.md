# Documentation TODO

Notes and tasks for improving the documentation.

## Sidebar Changes

- [x] Change "Tutorial" → "Tutorial: House Elevation" in `docs/_quarto.yml` line 18

## Landing Page (`docs/index.qmd`)

- [x] Replace "corny" opening: "SimOptDecisions helps you find good decision strategies when the future is uncertain."
  - New: "SimOptDecisions is a Julia framework for conducting exploratory modeling and simulation-optimization under uncertainty."
  - Next paragraph: "You provide a simulation model and parameterized policy. The framework runs your model, aggregates the results, and facilitates visualization and policy search."
  - Add: Designed to be flexible but imposes just enough structure to enable type stability, fast execution, and ergonomic APIs.

- [x] Under "Key Vocabulary": Add note that "Scenario" is sometimes called "State of the World" (SOW) in the decision analysis literature

- [x] "How It Works" section:
  - [x] Remove the first ASCII box ("You define" types and callbacks) - redundant with Quick Reference
  - [x] Keep the "Callback Flow" diagram - verify it's correct
  - [x] Replaced ASCII callback flow with Mermaid diagram (left-to-right layout)

## The Problem Page (`docs/tutorial/01-the-problem.qmd`)

- [x] Added "Code Patterns You'll See" section explaining:
  - [x] `T<:AbstractFloat` - parametric types for type stability
  - [x] `<:AbstractConfig`, `<:AbstractScenario`, etc. - how the framework knows your types
  - [x] Parameter types requirement (ContinuousParameter, etc.)

## Defining Your Model (`docs/tutorial/02-defining-your-model.qmd`)

**DONE** - Updated to use parameter types:

- [x] Update `HouseElevationConfig` - explain that Config can use plain types or parameters
- [x] Update `HouseElevationScenario` to use `ContinuousParameter` for all fields
- [x] Update `ElevationPolicy` to use `ContinuousParameter`
- [x] Update `sample_scenario()` to construct with parameters
- [x] Explain that parameter types enable:
  - Automatic bounds for optimization
  - Automatic flattening for exploratory modeling
  - Consistent visualization
  - Type-safe value extraction with `value()`

## Running a Simulation (`docs/tutorial/03-running-a-simulation.qmd`)

**DONE** - Updated to use parameter types:

- [x] Update type definitions to use `ContinuousParameter`
- [x] Update `run_timestep` to use `value()` for scenario parameters
- [x] Update `compute_outcome` to use `value()` for discount_rate
- [x] Update example code to construct policies with `ContinuousParameter`
- [x] Added code-fold to setup block

## Tutorial File Updates

- [x] Update `docs/tutorial/04-evaluating-a-policy.qmd` to use parameter types
- [x] Update `docs/tutorial/05-exploratory-modeling.qmd` to use parameter types
- [x] Update `docs/tutorial/06-policy-search.qmd` to use parameter types
- [x] Added code-fold to setup blocks in tutorials 03-06

## Parameter Types Documentation

Documented in tutorial 01-the-problem.qmd and 05-exploratory-modeling.qmd:

- [x] `ContinuousParameter{T}` - real values with optional bounds
- [x] `DiscreteParameter{T}` - integer values with optional valid_values
- [x] `CategoricalParameter{T}` - categorical with defined levels
- [x] `TimeSeriesParameter{T,I}` - time-indexed data that can be reused across different simulation horizons

## Validation Behavior

- [x] Document the `SIMOPT_STRICT_VALIDATION` environment variable in `docs/reference/validation.qmd`
  - When set to "true", validates that Scenario, Policy, and Outcome types use parameter fields at simulation time
  - Default is off (for backward compatibility)
  - `explore()` ALWAYS validates - parameter types are required there
- [x] Recommend users enable strict validation: `ENV["SIMOPT_STRICT_VALIDATION"] = "true"`

## Callback Flow Diagram

- [x] Replaced ASCII diagram with Mermaid in `docs/index.qmd`

## Other Notes

- [x] Remove any remaining references to "SOW" (should all be "scenario" now)
  - Updated persistence.qmd and validation.qmd
  - Only reference remaining is explanatory footnote in index.qmd
- [x] Ensure all code examples are runnable (verified - docs build successfully)
- [x] Add error message examples showing what happens with wrong types (in validation.qmd)
