# Sandbox: Daytona vs LangSmith

Ticket: #8 (map #1). Sources checked 2026-10-18. A claim with no source marked "not found" means the official page did not say.

## Answer

**LangSmith does sell a real sandbox product, so it competes with Daytona.** It is not only observability and eval. *LangSmith Sandboxes* are hardware-virtualized microVMs that run through the same `langsmith` SDK and API key as tracing. They were announced in private preview on 2026-03-17 and declared GA on 2026-05-13. Observability and eval remain LangSmith's core, so one LangSmith account can cover both tracing and execution. Daytona is execution only and pairs with any tracer.

For own-harness (one user, MacBook, small budget, TypeScript):

- **Isolation:** LangSmith documents microVMs, which is stronger on paper. Daytona sandboxes run as Linux containers by default, with a VM option.
- **Startup:** Daytona claims under 90 ms. LangSmith publishes no latency number.
- **TypeScript SDK:** Daytona's SDK is broader and more mature. LangSmith's is thinner and newer.
- **Cost at hobby scale:** Both are pennies an hour. Daytona gives a $200 one-time trial credit. LangSmith gives an $8/month recurring allowance, apparently on the free Developer plan (unconfirmed).
- **Local or offline:** Neither has a laptop-local mode you would want. Daytona's open-source self-host repo was archived in June 2026. LangSmith self-host needs Enterprise with Helm or Terraform.
- **Recommendation:** Hide the sandbox behind a small `Sandbox` interface in the harness. Start with a local Docker or no-sandbox backend for learning. Try Daytona first if you need a cloud one, because its startup claim, SDK breadth and trial credit fit best. Keep LangSmith in mind if you adopt it for tracing anyway.

## Comparison

| | Daytona | LangSmith Sandboxes |
|---|---|---|
| What it is | Execution-only sandbox platform | Sandbox product inside an observability/eval platform |
| Isolation | Linux containers by default, plus VM sandboxes created from VM snapshots. Docs say each gets "a dedicated kernel, filesystem, network stack" [D1]. The container runtime behind that claim is not named. | "hardware-virtualized microVM, kernel-isolated from your services and from other sandboxes" [L1]\[L2] |
| Default and max resources | 1 vCPU, 1 GB RAM, 3 GiB disk by default. Org max per sandbox is 4 vCPU, 8 GB, 10 GB [D1] | Set per Sandbox Template [L2]. No numbers found |
| Startup latency | "<90ms" (container) [D1]\[D3] | Not published. Warm pools mentioned [L2]. SDK start timeout defaults to 120 s, which is a ceiling and not a measurement [L5] |
| Network | Docs not checked in detail | "Restricted egress applies to non-Enterprise organizations by default" [L3] |
| TS SDK | `@daytona/sdk` (also `@daytonaio/sdk`) v0.225.0, published 2026-10-16, Apache-2.0 [N1]. Modules: Process, FileSystem, Git, CodeInterpreter, LspServer, ComputerUse, Pty, Snapshot, Volume, WarmPool and more. Runs on Node, Bun and Deno; the browser needs polyfills [D2] | `langsmith` v0.11.0, published 2026-10-15, MIT, `import { SandboxClient } from "langsmith/sandbox"` [N2]. The API covers create, start, stop, delete, run (WebSocket with HTTP fallback), snapshots from an image, Dockerfile or running sandbox, mounts (S3/GCS/git), and an auth proxy [N2]\[L4]. Smaller surface, and it moved out of `langsmith/experimental/sandbox` only recently |
| Pricing | $0.0504/vCPU-h, $0.0162/GiB-h RAM, $0.000108/GiB-h storage, billed per second. "Price per GiB after first 5 free" (scope unclear) [D4] | 1 LSU = $1. $0.0576/vCPU-h, $0.01845/GiB-h RAM, $0.000123/GiB-h storage, billed per second [L6]. About 14% above Daytona |
| Free tier | "$200 in free compute included" as a no-card trial [D4] | "Includes 8 LSU of Sandbox usage / mo for free" and "Limited to 10 Sandboxes" [L6]. The table appears to place this on the $0 Developer plan, but the plan mapping is unconfirmed |
| Local or offline | OSS Docker Compose self-host exists [D5], but github.com/daytonaio/daytona is **archived**. Its README says core development moved to a private codebase as of June 2026, and the last open release was v0.190.0 on 2026-06-23 [G1]. It is usable as-is with no updates | Self-hosted LangSmith supports sandboxes via Helm/Terraform [L3]. Self-hosted LangSmith is an Enterprise offering. A "sandbox on your laptop" mode is listed under "What's Coming Next" and does not exist yet [L1] |

Rough hobby cost: a default 1 vCPU / 1 GiB sandbox costs about $0.067/h on Daytona and about $0.076/h on LangSmith. That is computed from the rates above, before any free GiB allowance.

## Competes or complements?

They compete on execution, because both offer cloud sandboxes with an SDK.

LangSmith also covers tracing and eval, which Daytona does not do. Daytona sandboxes can still be traced by LangSmith or any other tracer, so the two can also be combined.

For a learning-first harness, the useful decision is architectural. Keep execution behind your own interface so you can swap the backend, and pick a tracer separately.

## Open questions

- LangSmith sandbox cold-start time: not published, so it needs a measurement.
- Whether LangSmith's free 8 LSU per month applies to the Developer plan: the pricing table is ambiguous once flattened. Check it in the app.
- Daytona's container runtime (what backs the "dedicated kernel" claim): not stated in the docs read.

## Sources (checked 2026-10-18)

- [D1] Daytona docs, Sandboxes: <https://www.daytona.io/docs/en/sandboxes/>
- [D2] Daytona docs, TypeScript SDK: <https://www.daytona.io/docs/en/typescript-sdk/>
- [D3] Daytona repo README: <https://github.com/daytonaio/daytona>
- [D4] Daytona pricing: <https://www.daytona.io/pricing>
- [D5] Daytona OSS deployment: <https://www.daytona.io/docs/en/oss-deployment>
- [G1] GitHub API: `daytonaio/daytona` archived=true, latest release v0.190.0 (2026-06-23), README maintenance notice
- [N1] npm registry: <https://registry.npmjs.org/@daytona/sdk> (source github.com/daytona/clients)
- [N2] npm registry and type defs: <https://unpkg.com/langsmith@0.11.0/lib/sandbox/index.d.ts>, `lib/sandbox/client.d.ts`
- [L1] LangChain blog, "LangSmith Sandboxes generally available" (2026-05-13): <https://www.langchain.com/blog/langsmith-sandboxes-generally-available>
- [L2] LangChain blog, "Introducing LangSmith Sandboxes" (2026-03-17): <https://www.langchain.com/blog/introducing-langsmith-sandboxes-secure-code-execution-for-agents>
- [L3] LangSmith docs, Sandboxes: <https://docs.langchain.com/langsmith/sandboxes>
- [L4] LangSmith JS reference: <https://reference.langchain.com/javascript/langsmith/sandbox>
- [L5] LangSmith Python reference, `SandboxClient.start_sandbox`: <https://reference.langchain.com/python/langsmith/sandbox/_client/SandboxClient/start_sandbox>
- [L6] LangChain pricing: <https://www.langchain.com/pricing>
