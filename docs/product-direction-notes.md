# Product Direction Notes

## Target Audiences

### Primary: Developers
- Engineering leads preparing ADRs, design reviews
- Developers onboarding to new codebases
- Platform teams integrating diagrams into CI

### Secondary: Vibe-Coders
- People shipping apps with AI assistance who may not fully understand the generated code
- Need a "explain my codebase to me" tool
- Growing audience as AI-assisted coding becomes mainstream

## Two-Mode Architecture

### Explorer Mode (Free)
- Plain-language UI, no UML jargon
  - "How your types are connected" instead of "class diagram"
  - "What happens when this function runs" instead of "sequence diagram"
  - "Which parts depend on each other" instead of "dependency graph"
- Drop a project folder, get a visual dashboard
- Contextual suggestions: "This file has 4 classes with inheritance — see how they connect"
- Guided insights: "DatabaseManager is used by 14 other types — changes here affect a lot"
- Limited to 1 project

### Developer Mode (Paid)
- Full PlantUML/Mermaid export
- Sequence diagrams with configurable call depth
- Dependency graphs, multi-module support
- Custom filtering, YAML config, stereotypes
- CLI access
- Unlimited projects

## Business Model: Low-Cost Subscription

### Pricing
- Target range: $3-5/month
- Low price removes friction for casual users already paying for AI tools
- Ongoing revenue funds ongoing Swift language support (yearly releases)

### Tier Structure

| Feature | Free | Pro ($3-5/mo) |
|---|---|---|
| Explorer mode | Yes | Yes |
| Basic class diagrams | Yes | Yes |
| Projects | 1 | Unlimited |
| Export (PlantUML/Mermaid) | No | Yes |
| Sequence diagrams | No | Yes |
| Dependency graphs | No | Yes |
| Architecture change tracking | No | Yes |
| CLI access | No | Yes |

### Reducing Churn
- **Project tracking over time** — show how architecture has changed since last week ("3 new types added, complexity increased in PaymentModule")
- **AI workflow integration** — let users paste diagrams into AI chat as context for prompting
- **Team sharing** — shareable diagram links or exports for code reviews

### Distribution
- Mac App Store for the GUI (freemium) — best channel for vibe-coder discovery
- Homebrew/GitHub for the CLI (open source) — developer funnel
- CLI stays free and open source to drive awareness; Studio app is where the business is

### App Store Considerations
- Apple requires clear ongoing value for subscription apps
- Architecture change tracking and ongoing Swift version support justify the model

## Sequencing
1. Ship v1.0 for developers (current milestone)
2. Build Explorer Mode as v2.0 headline feature with freemium model
3. Validate vibe-coder demand (landing page, signups) before heavy investment

## Open Questions
- Exact price point ($3 vs $5)
- Whether to validate demand before building Explorer Mode
- Whether the vibe-coder use case eventually warrants a separate, simpler product
