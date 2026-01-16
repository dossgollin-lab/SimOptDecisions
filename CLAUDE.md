# Claude Instructions

Before making code changes, read [STYLE.md](STYLE.md) for project conventions.

## Key Rules

1. **Use parametric types** - Always use `T<:AbstractFloat` instead of `Float64` for numeric fields
2. **Keep docstrings minimal** - 1-2 lines for simple functions, structured format for complex ones
3. **Interface methods** - Use `interface_not_implemented()` helper for fallback errors
4. **No over-engineering** - Avoid abstractions unless clearly needed
5. Keep git commits short and do not name coauthors or add email addresses
6. **Explicit failure over silent wrong behavior** - Never provide "convenience" constructors that silently pick defaults (e.g., `Foo(values) = Foo(first(values), values)`). If required information is missing, throw an error with a helpful message
