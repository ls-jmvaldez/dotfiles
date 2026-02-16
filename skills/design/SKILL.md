---
name: design
description: Enforces precise, minimal design for dashboards and admin interfaces. Use when building SaaS UIs, data-heavy interfaces, or any product needing high-craft visual design.
license: MIT
compatibility: opencode
---

# Design Principles

**Core philosophy:** Every interface should look designed by a team that obsesses over 1-pixel differences. Not stripped, _crafted_. And designed for its specific context.

## Design Direction (REQUIRED)

**Before writing code, commit to a direction.** Don't default. Think about what this specific product needs to feel like.

### Think About Context

- **What does this product do?** A finance tool needs different energy than a creative tool.
- **Who uses it?** Power users want density. Occasional users want guidance.
- **What's the emotional job?** Trust? Efficiency? Delight? Focus?
- **What would make this memorable?** Every product has a chance to feel distinctive.

### Choose a Personality

| Direction | Feel | When to Use |
|-----------|------|-------------|
| Precision & Density | Tight spacing, monochrome, info-forward | Power users who live in the tool. Linear, Raycast, terminal aesthetics. |
| Warmth & Approachability | Generous spacing, soft shadows, friendly | Products that want to feel human. Notion, Coda, collaborative tools. |
| Sophistication & Trust | Cool tones, layered depth, gravitas | Products handling money or sensitive data. Stripe, Mercury. |
| Boldness & Clarity | High contrast, dramatic negative space | Modern, decisive products. Vercel, minimal dashboards. |
| Utility & Function | Muted palette, functional density | Work matters more than chrome. GitHub, developer tools. |

Pick one. Or blend two. But commit to a direction that fits the product.

## Core Craft (Non-Negotiable)

### The 4px Grid

All spacing uses 4px base: `4px` (micro), `8px` (tight), `12px` (standard), `16px` (comfortable), `24px` (generous), `32px` (major).

### Symmetrical Padding

TLBR must match. If top is 16px, all sides are 16px. Exception: when content naturally creates visual balance.

### Border Radius

Stick to 4px grid. Pick a system and commit:
- Sharp: 4px, 6px, 8px
- Soft: 8px, 12px
- Minimal: 2px, 4px, 6px

### Typography Hierarchy

- Headlines: 600 weight, -0.02em tracking
- Body: 400-500 weight
- Labels: 500 weight, positive tracking for uppercase
- Scale: 11px, 12px, 13px, 14px (base), 16px, 18px, 24px, 32px

Use **monospace** for numbers, IDs, codes, timestamps. Use `tabular-nums` for columns.

### Color for Meaning Only

Gray builds structure. Color only appears when it communicates: status, action, error, success. Four-level contrast hierarchy: foreground -> secondary -> muted -> faint.

## Motion & Animation

**Motion is communication, not decoration.** Every animation should have a reason.

- **Timing:** 150-200ms for micro-interactions, 300-400ms for larger transitions
- **Easing:** `ease-out` for entrances, `ease-in` for exits, `ease-in-out` for state changes
- **Staggered reveals:** When loading multiple items, stagger by 50-75ms for polished feel

Avoid: Spring physics, bouncy overshoots, parallax effects. Keep motion functional.

## Anti-Patterns

Never:
- Dramatic drop shadows (`0 25px 50px...`)
- Large radius (16px+) on small elements
- Asymmetric padding without reason
- Pure white cards on colored backgrounds
- Thick borders (2px+) for decoration
- Spring/bouncy animations
- Multiple accent colors
- Motion without purpose

## The Standard

Different products want different things. A dev tool wants precision and density. A collaborative product wants warmth and space. A financial product wants trust and sophistication.

**Same quality bar, context-driven execution.**
