[中文文档](README_zh-CN.md)

# Shepherd 🐑

**Subagent Watchdog for OpenClaw**

The shepherd — guiding and guarding every subagent task.

## Problem

OpenClaw subagent timeout rate is 19.4%, accounting for 71.3% of all failures. The current mechanism uses a one-size-fits-all fixed threshold, unable to distinguish between "working but slow" and "truly dead."

## Solution

A hybrid architecture: local layer handles the skeleton (deterministic, millisecond-level), LLM handles judgment (intelligent diagnostics, on-demand).

### Core Modules

| Module | Layer | Responsibility |
|--------|-------|----------------|
| Task Classifier | Local | Keyword matching → task type → timeout strategy |
| Heartbeat Engine | Local | File heartbeat protocol, detects "alive or dead" |
| Dynamic Timeout | Local | Activity timeout, renews if heartbeat is healthy |
| Progress Tracker | Local | Records execution steps, supports resume from breakpoint |
| Timeout Diagnosis | LLM | Post-kill analysis of cause, determines re-dispatch strategy |
| Anomaly Detection | Hybrid | Local anomaly detection → LLM root cause diagnosis |
| Stats Dashboard | Local | Real-time metrics + weekly report analysis |

## Expected Outcomes

| Metric | Current | Target |
|--------|---------|--------|
| Timeout Rate | 19.4% | < 8% |
| Coding Completion Rate | 57% | > 80% |
| False Kill Rate | High | Very Low |

## Architecture

```
┌─────────────────────────────────────────────┐
│           Local Layer (Deterministic)         │
│  Heartbeat → Time Threshold → Renew/Kill     │
│  Progress Tracker → File Change Detection    │
│  Stats Dashboard → Data Aggregation          │
└───────────────────────┬─────────────────────┘
                        │ Trigger Conditions
                        ↓
┌─────────────────────────────────────────────┐
│            LLM Layer (Intelligent)           │
│  Timeout Diagnosis → Re-dispatch → Anomaly  │
│  Analysis → Weekly Report                   │
└─────────────────────────────────────────────┘
```

## Development Status

- [x] Project initialization
- [x] Task classifier
- [x] Heartbeat engine
- [x] Dynamic timeout
- [x] Progress tracker
- [x] Timeout diagnosis (LLM)
- [x] Stats dashboard
- [ ] OpenClaw plugin packaging
- [x] Testing
- [x] Release

## License

MIT
