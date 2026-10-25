# NemoClaw: what it is, and does it fit own-harness?

Research for issue #7. Sources checked 2026-10-18, mostly the NVIDIA repos and docs themselves.

## Answer

NemoClaw is real. It is **NVIDIA's open-source (Apache-2.0) "reference stack"** for running existing third-party agents (OpenClaw by default, plus Hermes and LangChain Deep Agents Code) inside **NVIDIA OpenShell** sandboxes. It adds managed inference, network and filesystem policy, and lifecycle tooling. It wraps *someone else's* agent runtime in a container, so it is the wrong shape for a hand-written TypeScript core loop. **It does not fit own-harness.** The useful lesson is its design: deny-by-default egress, credentials kept out of the sandbox, and operator approval for new access. Copy that at a lighter weight (see Alternatives).

## What it is

- "An open source reference stack for running supported AI agents more safely" inside NVIDIA OpenShell sandboxes. Supports OpenClaw (default), Hermes, and LangChain Deep Agents Code. [GitHub NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw)
- Maker: NVIDIA. Repo created 2026-03-15. License Apache-2.0. Mostly TypeScript (host CLI), plus Shell, Python, and Dockerfiles. (GitHub API, `repos/NVIDIA/NemoClaw`)
- Status: **alpha**. Maintainers respond "on a best effort basis" (repo README). Doc versions run 0.0.x ([docs.nvidia.com/nemoclaw](https://docs.nvidia.com/nemoclaw/0.0.16/index.html)).
- Parts: a host CLI (`nemoclaw onboard` etc.), a versioned YAML **blueprint** (sandbox image, agent manifest, network policy, inference profile) whose digest is checked before it is applied, and an agent-specific integration layer that runs inside the sandbox. NemoClaw "does not replace OpenShell or the selected agent runtime". [docs/about/how-it-works.mdx](https://github.com/NVIDIA/NemoClaw/blob/main/docs/about/how-it-works.mdx)
- **OpenShell** (separate NVIDIA repo, Rust, Apache-2.0) is the runtime that actually enforces policy: a gateway plus per-agent sandboxes. [NVIDIA/OpenShell README](https://github.com/NVIDIA/OpenShell)

## Security guarantees

These are enforced by OpenShell. NemoClaw configures them.

- **Sandboxing:** each agent runs in an isolated sandbox. "Kernel controls confine which files it can access and which system calls it can make." (OpenShell README) NemoClaw adds container hardening, capability drops, and process limits (NemoClaw README; [docs/security/](https://github.com/NVIDIA/NemoClaw/tree/main/docs/security)).
- **Network policy:** every connection goes through a policy check. Egress is controlled, and an operator approves new access. (OpenShell README; [NemoClaw docs index](https://docs.nvidia.com/nemoclaw/0.0.16/index.html))
- **Credential custody:** agents never see real API keys. OpenShell inserts them only into requests bound for approved endpoints. [how-it-works.mdx](https://github.com/NVIDIA/NemoClaw/blob/main/docs/about/how-it-works.mdx)
- **Policy review:** OpenShell uses "formal verification" to flag risky new access before a policy change is approved (OpenShell README).
- **Stated limits:** the agent process and its writable state are untrusted. NemoClaw "does not provide post-provisioning immutability" for agent config or state. In the OpenShell-managed topology, supervisor, gateway, and agent all run as the same `sandbox` user, so there is no user-ID isolation. [docs/security/tcb-boundary.mdx](https://github.com/NVIDIA/NemoClaw/blob/main/docs/security/tcb-boundary.mdx)
- **Guardrails (content):** the pages I read describe **access control, not prompt or output content filtering**. I found no claim that NemoClaw does LLM content guardrails like NeMo Guardrails.

## What it needs to run

[docs/get-started/prerequisites.mdx](https://github.com/NVIDIA/NemoClaw/blob/main/docs/get-started/prerequisites.mdx):

- Hardware: minimum 4 vCPU, 8 GB RAM, 20 GB disk. Recommended 16 GB RAM and 40 GB disk. The sandbox image is about 2.4 GB compressed. No GPU is needed on the host when you use hosted inference.
- Software: Node.js 22.19+, npm 10+, and a container runtime (Docker Desktop or Colima on macOS). It runs k3s plus the OpenShell gateway.
- Platforms: Linux and DGX Spark are the primary tested paths. **macOS (Apple Silicon) is "Tested with limitations"** via Colima or Docker Desktop. WSL2 is also tested with limitations.
- Inference: NVIDIA Endpoints (build.nvidia.com, e.g. Nemotron), other hosted providers, or local Ollama, vLLM, llama.cpp, or NIM ([overview.mdx](https://github.com/NVIDIA/NemoClaw/blob/main/docs/about/overview.mdx)).
- License: Apache-2.0. No paid license is required. Hosted inference providers have their own terms.

## Fit for own-harness

**Doesn't fit as a dependency:**

- It sandboxes *supported agent runtimes* (OpenClaw, Hermes, Deep Agents). It is not a library you call from your own loop. Using it means adopting their agent, which defeats a learning-first, hand-written core.
- Heavy for one user on a MacBook: Docker or Colima, k3s, a gateway, about 2.4 GB of images, and 8 to 16 GB RAM. macOS is a second-tier platform, and the project is alpha.
- Built for always-on, unattended fleets ("fleets of autonomous AI agents"). A personal CLI research assistant has a much smaller threat surface.

**Worth stealing as ideas:** deny-by-default network egress with an allowlist, secrets kept outside the agent's reach, a human approval prompt for new access, and an explicit statement of what is trusted and what is untrusted.

## Alternatives

1. **Anthropic Sandbox Runtime (`@anthropic-ai/sandbox-runtime`, `srt`).** TypeScript, Apache-2.0, beta. It wraps any process in OS-native sandboxing (`sandbox-exec` on macOS, bubblewrap on Linux) with a filesystem policy and a proxy-based network allowlist, and needs no container. It is the closest fit for sandboxing the shell and tool calls a harness makes. [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
2. **OpenShell directly.** This is the NVIDIA runtime underneath NemoClaw, without the agent packaging. It runs on macOS Apple Silicon and has a TypeScript SDK (`@nvidia/openshell-sdk`, from GitHub Packages). It is still container or VM based and heavier than `srt`. [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell)
3. **A permission gate inside the harness** (my design suggestion, not a product). The core loop checks each tool call against a per-tool allowlist policy and asks the user y/n for anything outside it, with secrets read only by the host. It is cheap, it teaches the concepts, and it pairs well with 1. For *content* guardrails (prompt or output filtering), NVIDIA's NeMo Guardrails exists, but it is Python ([NVIDIA-NeMo/Guardrails](https://github.com/NVIDIA-NeMo/Guardrails)), so it fits a TS harness poorly.
