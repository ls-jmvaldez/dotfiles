---
name: handling-errors
description: Prevents silent failures and context loss in error handling. Use when writing try-catch blocks, designing error propagation, reviewing catch blocks, or implementing Result patterns.
license: MIT
compatibility: opencode
---

# Handling Errors

## Iron Laws

1. **Never swallow errors** - Empty catch blocks hide bugs
2. **Never convert errors to booleans** - Loses all context
3. **Preserve error context** when wrapping or propagating
4. **Log once where handled**, not at every layer

## Error Messages

Every error message answers: **What happened? Why? How to recover?**

**For logs (developers):**

```typescript
logger.error("Failed to save user: Connection timeout after 30s", {
  userId: user.id,
  dbHost: config.db.host,
  error: error.stack,
});
```

**For users:**

- Brief and specific (not "Something went wrong")
- Actionable (tell them what to do next)
- No blame (never "You entered invalid...")

```typescript
showError({
  title: "Upload failed",
  message: "File exceeds 10MB limit. Choose a smaller file.",
  actions: [{ label: "Choose file", onClick: selectFile }],
});
```

## Error Categories

| Type         | Examples                           | Handling                    |
| ------------ | ---------------------------------- | --------------------------- |
| **Expected** | Validation, Not found, Unauthorized| Return Result type, log info|
| **Transient**| Network timeout, Rate limit        | Retry with backoff, log warn|
| **Unexpected**| Null reference, DB crash          | Log error, show support ID  |
| **Critical** | Auth down, Payment gateway offline | Circuit breaker, alert      |

## Fail Fast vs Degrade Gracefully

**Fail fast** for critical dependencies:

```typescript
await connectToDatabase(); // Throws on failure - app can't run without it
```

**Degrade gracefully** for optional features:

```typescript
const prefs = await loadPreferences(userId).catch(() => DEFAULT_PREFS);
```

## Log at the Right Layer

```typescript
// BAD: Logging at every layer = same error 3x
async function fetchData() {
  try { return await fetch(url); }
  catch (e) { console.error("Fetch failed:", e); throw e; }
}

// GOOD: Log once where handled
async function fetchData() {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response;
}
// Top level logs the error once
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Empty catch blocks | Hides errors | Log or re-throw |
| `return false` on error | Loses context | Return Result type |
| Generic "Error" messages | Undebuggable | Include what/why/context |
| Logging same error at each layer | Log pollution | Log once at boundary |
| Bare `except:` / `catch (e)` all | Catches system signals | Catch specific types |
