---
name: research
description: Conduct structured technical or academic research with explicit question framing, traceable search scope, source-quality assessment, evidence synthesis, citations, uncertainty, and next-step recommendations. Use for literature reviews, technical surveys, method comparisons, and evidence-based planning.
compatibility: Requires access to relevant source material; web or literature-search tools are optional and must be available separately.
---

# Research

Use this workflow to produce traceable evidence rather than an unstructured answer.

Read [references/evidence-policy.md](references/evidence-policy.md) when source quality, conflicting evidence, or academic claims matter.

## 1. Frame the question

- State the research question and intended decision or deliverable.
- Distinguish exploration, comparison, validation, prediction, association, and causality.
- Define population, system, time range, methods, outcomes, and exclusions when relevant.

## 2. Plan retrieval

- Build a compact query set using synonyms and domain terms.
- Identify the preferred source classes before searching.
- Use current sources for time-sensitive claims.
- If no search or source-access tool is available, say so and work only from supplied material.

## 3. Gather traceable evidence

- Prefer primary papers, official documentation, standards, datasets, and first-party reports.
- Record title, source, date, identifier or URL, and the claim each source supports.
- Do not treat a search-result snippet or inaccessible abstract as full evidence.
- Avoid repeated sources that do not add independent support.

## 4. Evaluate evidence

For each important claim, distinguish:

- direct source fact;
- author interpretation;
- model synthesis;
- model inference;
- unresolved uncertainty.

Identify conflicts in definitions, samples, preprocessing, metrics, or evaluation units before comparing results.

## 5. Synthesize for the decision

- Answer the question directly before giving background.
- Explain what each cited result establishes and what it does not establish.
- Preserve negative, conflicting, and inconclusive evidence.
- Do not rank methods from one metric when the decision is multi-dimensional.

## 6. Recommend the next step

Recommendations must follow from the evidence and state assumptions, risks, and validation needs.

## Output format

```markdown
## Research question

## Search scope

## Evidence

## Synthesis

## Limitations

## Recommended next step

## Sources
```

Use the knowledge-capture skill only when the user asks to preserve the result or the active workflow explicitly includes durable capture.
