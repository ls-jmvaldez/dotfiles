---
name: architecting-systems
description: Guides clean, scalable system architecture during the build phase. Use when designing modules, defining boundaries, structuring projects, managing dependencies, or preventing tight coupling and brittleness as systems grow.
license: MIT
compatibility: opencode
---

# Architecting Systems

**Core principle:** Small decisions made early compound into either clean systems or massive technical debt. Get the structure right and the system stays maintainable as it grows.

## Core Principles

### Convention over invention

Default to established patterns, standard libraries, and proven conventions. Novel solutions carry hidden costs: documentation burden, onboarding friction, and maintenance surprises.

| Prefer | Over |
|--------|------|
| Framework conventions | Custom project structures |
| Standard library tools | Bespoke utilities for solved problems |
| Established patterns (MVC, repository, etc.) | Clever abstractions |
| Boring technology that works | Exciting technology that might |

**The test:** If someone new joins the team, how quickly can they find things and understand the structure?

### State management

State is where complexity hides. The more places state lives and the more things can mutate it, the harder the system is to reason about.

- **Minimize mutable shared state.** If two modules need the same data, one should own it and the other should request it.
- **Keep state close to where it's used.** Global state is almost never the answer.
- **Make state changes explicit.** Whether that's through events, reducers, or explicit setter methods.
- **Single source of truth.** Every piece of data should have one authoritative home.

### Design for change

- **Make the common path easy.** Good defaults, templates, and guard rails beat documentation.
- **Enforce with tooling, not docs.** Linting rules, CI checks, and architectural tests scale. Wiki pages don't.
- **Isolate volatility.** Wrap external integrations in adapters. Isolate business rules in the domain layer.
- **Prefer composition over inheritance.** Combine small, focused pieces rather than extending complex base classes.

### Complexity budget

Every architectural decision has a complexity cost. Spend that budget where it matters.

| Worth the complexity | Not worth it |
|---------------------|--------------|
| Separation between domains that change independently | Abstracting code that only has one implementation |
| Event-driven for genuinely async workflows | Event-driven for simple request-response flows |
| Caching for measured performance bottlenecks | Caching "just in case" |
| Microservices for teams that deploy independently | Microservices for a small team's monolith |

**The rule:** Don't add indirection until you need it. Premature abstraction is as costly as premature optimization.

## Quick Reference

| Problem | Response |
|---------|----------|
| "Where does this code go?" | If the answer isn't obvious, the structure needs work |
| "Changing X requires touching Y" | Missing boundary between X and Y |
| "This module does too many things" | Split along separate reasons to change |
| "We can't test this in isolation" | Hidden dependencies; inject them instead |
| "New devs take weeks to be productive" | Conventions are too weak or too novel |
| "Every PR touches 10 files" | Feature code is scattered; colocate it |
| "The shared folder keeps growing" | Boundaries are in the wrong place |
