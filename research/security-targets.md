# Safe targets, labs and legal limits for a security learning project

Research for [#21](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/21) (feeds [#22](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/22)). Checked **2026-10-18**. Not legal advice.

Markers: **[verified]** = read on the primary source on the check date. **[snippet]** = seen only in a search-result excerpt of the primary source (the page itself blocked fetching). **[unverified]** = from memory or a secondary source; confirm before relying on it.

## TL;DR

- **Best targets: local labs on your Mac, bound to `127.0.0.1`.** Juice Shop, WebGoat and DVWA all publish arm64 images. Vulhub covers real CVEs, and most of its environments run on M-series Macs. Metasploitable 2 is x86-only, so skip it or emulate it.
- **To learn agent and LLM security, use DVMCP (vulnerable MCP servers) and Damn Vulnerable LLM Agent.** Run the vulnerable agent's own LLM **locally (Ollama)**, not through OpenRouter. OpenRouter's terms ban prompt-injection and jailbreak testing ("red teaming") without prior written approval.
- **CTF platforms mostly forbid agents driving them.** TryHackMe explicitly bans AI agents and using its content to train or evaluate AI. HTB bans training AI on its content and says to hack only the provided targets. picoCTF bans attacking anything not designated as a target. Use them by hand, or have the agent work only on downloaded or retired challenge files.
- **Datasets are free to use with attribution:** NVD, CWE, ATT&CK (STIX), Sigma (DRL 1.1), Splunk BOTS v3 (CC0, but it needs Splunk) and OTRF Security-Datasets.
- **Law:** in Hungary, entering a system without authorisation by breaking or bypassing its protection is a crime (Btk. §423). So is making or distributing tools or passwords for that purpose (§424). EU Directive 2013/40/EU sets the common baseline. **Authorisation, in writing and with a defined scope, is the whole game.**

---

## 1. Local intentionally vulnerable labs (Apple Silicon and Docker)

| Lab | What you learn | Run | arm64? | License | Notes |
|---|---|---|---|---|---|
| **OWASP Juice Shop** | Modern web app (OWASP Top 10, about 100 challenges) | `docker run --rm -p 127.0.0.1:3000:3000 bkimminich/juice-shop` | **Yes**: amd64 and arm64 on Docker Hub `latest` (updated 2026-10-12) [verified] | MIT [verified] | The README's own command binds to loopback. |
| **DVWA** | Classic PHP vulns at adjustable difficulty | `docker compose up -d` from the repo, at `http://localhost:4280` | **Yes** for `ghcr.io/digininja/dvwa:latest` (amd64 and arm64). The old `vulnerables/web-dvwa` image is amd64-only and dates from 2018 [verified via registry API] | GPL-3.0 [verified] | The README says not to put it on any Internet-facing server. The compose file binds to `127.0.0.1` by default and sets `restart: unless-stopped`, so it auto-starts with Docker [verified]. |
| **OWASP WebGoat** | Guided lessons (Java) plus WebWolf | `docker run -it -p 127.0.0.1:8080:8080 -p 127.0.0.1:9090:9090 webgoat/webgoat` | **Yes**: amd64 and arm64 on Docker Hub `latest` (updated 2026-10-12) [verified] | License file not read [unverified] | The README warns the machine is "extremely vulnerable" while it runs [verified]. |
| **Vulhub** | Real-world CVEs, one `docker compose` per CVE | `cd <env> && docker compose up -d` | "Most environments" run natively on M-series Macs. If one doesn't, use `DOCKER_DEFAULT_PLATFORM=linux/amd64` [verified] | MIT [verified] | "Do not use in production!" This is the best **Metasploitable alternative** for real CVE practice. |
| **Metasploitable 2** | Old Linux box with many services | VM image | **No**: x86_64 only. It can run under UTM/QEMU emulation, but slowly [secondary source: VMware forum] | n/a | Not recommended on this Mac. |
| **Damn Vulnerable MCP Server (DVMCP)** | 10 MCP challenges: prompt injection, tool poisoning, excessive scope, rug pull, tool shadowing, indirect injection, token theft, code execution, remote access, multi-vector [verified] | `docker build -t dvmcp . && docker run -p 127.0.0.1:9001-9010:9001-9010 dvmcp` | Builds locally, so it follows your architecture (not tested) | MIT (per README) [verified] | **The README's command is `-p 9001-9010:9001-9010`, which listens on all interfaces. Add `127.0.0.1:`.** This lab maps directly onto dsh's MCP plugin. |
| **Damn Vulnerable LLM Agent (WithSecure)** | ReAct-agent Thought/Action/Observation injection (LangChain, Streamlit) | `docker build -t dvla . && docker run --env-file env.list -p 127.0.0.1:8501:8501 dvla` | Builds locally | Apache-2.0 [verified] | Supports OpenAI, HuggingFace or **Ollama (local)**. The README notes that small models do poorly as ReAct agents [verified]. Use Ollama to stay clear of OpenRouter's red-teaming rule (section 5). |
| **Gandalf / Agent Breaker (Lakera)** | Hosted prompt-injection game | Browser only. `gandalf.lakera.ai` now redirects to `play.lakera.ai/agent-breaker` [verified] | n/a | Proprietary | Hosted, not local. Lakera says gameplay feeds its products [snippet], so assume your prompts are collected. No terms on automation found [unverified]. **Play it by hand. Don't point the agent at it.** |

**Docker exposure gotcha.** Docker's docs say "Publishing container ports is insecure by default". By default it publishes to all host addresses. Binding to `127.0.0.1` limits access to the host, though releases older than 28.0.0 let hosts on the same L2 segment reach localhost-published ports [verified, [docs](https://docs.docker.com/engine/network/port-publishing/)]. So prefix **every** `-p` with `127.0.0.1:` and keep Docker 28 or later.

**For an agent harness**, the natural progression is: Juice Shop (web, with clear scoreboard feedback), then Vulhub CVEs, then DVMCP and DVLA (attacking agents, a mirror of what the harness itself is).

Sources: [Juice Shop](https://github.com/juice-shop/juice-shop) · [DVWA](https://github.com/digininja/DVWA) · [WebGoat](https://github.com/WebGoat/WebGoat) · [Vulhub](https://github.com/vulhub/vulhub) · [DVMCP](https://github.com/harishsg993010/damn-vulnerable-MCP-server) · [DVLA](https://github.com/WithSecureLabs/damn-vulnerable-llm-agent) · Docker Hub `v2/repositories/<repo>/tags/latest` and the GHCR manifest API (architectures)

## 2. CTF platforms and their rules on automation and AI

| Platform | Targets you may hit | Automation / AI agents | Sharing and AI training | Source |
|---|---|---|---|---|
| **TryHackMe** | Only labs, machines and IP ranges assigned to you, or systems you own or have written authorisation to test. The platform itself is out of scope except under its VDP. No pivoting out of labs [verified] | **Banned**: bots, crawlers, headless browsers, automation frameworks and **AI agents**, unless through a TryHackMe-provided interface. It says it is "not fine" to hand an agent your credentials. Asking an AI assistant to explain a concept is fine [verified] | No flags or walkthroughs for active content. Content may not be used to "train, fine-tune, **evaluate**, or improve" AI or ML models [verified] | [AUP](https://tryhackme.com/legal/acceptable-use-policy), [ToU](https://tryhackme.com/legal/terms-of-use) |
| **Hack The Box** | "Hack only the provided targets". No gateways or non-target nodes, no DoS, no attacking other players [verified] | The platform-rules article says nothing explicit about bots or agents [verified]. The 2026-04-01 AUP PDF could not be text-extracted [unverified] | Writeups for **retired** content only. "Do not train AI on HTB Content" [verified]. The fetch summarised this as also covering *testing* AI; confirm the exact wording | [Platform rules](https://help.hackthebox.com/en/articles/12325897-hack-the-box-platform-rules), [Writeup guidelines](https://help.hackthebox.com/en/articles/5188925-streaming-writeups-walkthrough-guidelines), [AUP PDF](https://www.hackthebox.com/hubfs/Legal/AUP.pdf) |
| **picoCTF / picoGym** | Attacking the scoring server, other users, or "machines not explicitly designated as targets" counts as cheating. No disrupting the service [snippet: the site returned 403 to the fetcher] | No AI or automation rule found [unverified] | Competition rules forbid sharing flags [unverified for 2026] | [Terms](https://picoctf.org/terms.html), [2025 rules](https://picoctf.org/competitions/2025-spring-rules.html) |
| **CTFtime events** | Each event sets its own rules. CTFtime's FAQ has no AI policy [verified] | Varies. CSAW 2025 ran an *agentic* track where agents were required. UMassCTF 2026 created a human-only "Old Fashioned" division [secondary sources] | Per event | [CTFtime FAQ](https://ctftime.org/faq/), [Include Security, Apr 2026](https://blog.includesecurity.com/2026/04/ctfs-in-the-ai-era/) |

**Takeaway.** Don't let the harness log into TryHackMe or HTB. Practise there by hand. For agent runs, use local labs, **past CTF challenges you have downloaded and run locally**, or live events that explicitly allow agents (read each event's rules first). Don't build Promptfoo eval sets from TryHackMe or HTB content.

## 3. Public datasets (defensive and analysis side)

| Dataset | What | Access / format | License / terms |
|---|---|---|---|
| **NVD (CVE)** | CVE records with CVSS, CPE, and now SSVC data (added 2026-06-17) [snippet] | REST API 2.0. Rate limiting returns **429** (since 2025-05-19). API keys come from a web form [snippet] | Public. Rate limits often quoted as 5 requests per 30 s without a key and 50 with one, plus a recommended sleep **[unverified: the docs pages didn't render]** |
| **CWE** | Weakness taxonomy | Downloads page (XML/CSV) [unverified formats] | Royalty-free licence for research and commercial use. Keep MITRE's copyright notice [verified, [terms](https://cwe.mitre.org/about/termsofuse.html)] |
| **MITRE ATT&CK** | Adversary tactics and techniques | STIX 2.1 bundles for enterprise, mobile and ICS, per release plus "latest" [verified, [attack-stix-data](https://github.com/mitre-attack/attack-stix-data)] | Royalty-free. Keep the "© 2026 The MITRE Corporation…" notice [verified, [ToU](https://attack.mitre.org/resources/legal-and-branding/terms-of-use/)] |
| **Sigma rules** | Over 3,000 detection rules (generic, hunting, emerging threats, compliance) | YAML. Convert with `sigma-cli` or pySigma [verified, [SigmaHQ](https://github.com/SigmaHQ/sigma)] | **Detection Rule License 1.1** (attribution) [verified] |
| **Splunk BOTS v3** | Blue-team CTF dataset | About 320 MB, pre-indexed **Splunk** app. Needs Splunk Enterprise 7.1.7 and about two dozen add-ons [verified, [botsv3](https://github.com/splunk/botsv3)] | CC0-1.0 (the add-ons are licensed separately). May contain profanity |
| **OTRF Security-Datasets** (formerly "Mordor" [unverified]) | Malicious and benign event recordings to replay | Formats not stated on README [unverified] | README says GPL-3.0 but the sidebar says MIT; this conflict is unresolved [verified, [repo](https://github.com/OTRF/Security-Datasets)] |

Datasets are the **zero-legal-risk** option. "Explain this CVE", "map these logs to ATT&CK" or "write or convert a Sigma rule" are all purely defensive tasks that cheap models handle without hitting refusals or policy trouble.

## 4. Legal and ethical limits (high level, not legal advice)

### EU: Directive 2013/40/EU (attacks against information systems) [verified, [EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32013L0040)]

- "Without right" means not authorised by the owner or another rights holder, or not permitted by national law (Art. 2(d)).
- Offences: illegal access by infringing a security measure (Art. 3), illegal system interference (Art. 4), illegal data interference (Art. 5), illegal interception (Art. 6), and **tools**, meaning programmes or passwords made available with intent to commit those offences (Art. 7).
- Member States must criminalise these "at least for cases which are not minor".
- Council of Europe Budapest Convention (ETS 185): Hungary is a party **[unverified: the CoE page returned 403]**.

### Hungary: Btk. (Act C of 2012), Chapter XLIII [verified, [Jogtár](https://net.jogtar.hu/jogszabaly?docid=a1200100.tv)]

- **§423 Violation of an information system or data.** Entering a system without authorisation by breaking or bypassing its technical protection, or staying in it beyond your rights: misdemeanour, up to 2 years. Interfering with operation or altering or deleting data: felony, up to 3 years. Significant number of systems or significant harm: 1 to 5 years. Against a public-utility enterprise: 2 to 8 years.
- **§424 Circumventing technical protection of an information system.** Making, handing over, acquiring or distributing passwords or programs that facilitate §423, §422(1)(d) or §375 offences, or sharing know-how for making them: misdemeanour, up to 2 years. §424(2) lets you avoid punishment if you report to the authorities before they learn of it. Relevance here: **don't publish weaponised exploit tooling or harvested credentials from this project.**
- **§422 Unlawful data acquisition.** Includes covertly snooping on data in an information system to obtain personal data or secrets: up to 3 years.
- §375 (fraud using an information system) is referenced by §424. It was not read in detail.

### Practical meaning

- The labs on **your own Mac** that **you** installed are systems you are entitled to test. Everything else needs **explicit, preferably written, authorisation with a defined scope** (hosts, time window, techniques).
- Platform labs: their AUP is your authorisation, and its scope is exactly the assigned targets (section 2).
- Bug bounties and VDPs are authorisation only within their published scope. Out of scope here.
- An autonomous agent does not shift responsibility. **What it touches, you touched.** So the scope must be enforced in code (allowlist), not just written in the prompt.

## 5. OpenRouter and model providers on offensive-security prompts

### OpenRouter (Terms, last updated 2026-08-31) [verified, [terms](https://openrouter.ai/terms), [red-teaming policy](https://openrouter.ai/docs/guides/evaluate-and-optimize/red-teaming)]

- **§5.1:** by using any model you agree to **that model's terms** too. You must check whether they allow your use.
- **§7 prohibited:** illegal purposes, breaking model terms, spreading malware, accessing others' accounts without permission, and more.
- **§8 red teaming** covers prompt injection, jailbreaking, or adversarial action "designed to compromise any Models". The docs define it as testing "AI applications and/or models" for those. It needs **prior written approval**: email `safety@openrouter.ai` with the use case, models, providers, techniques and timeline. Approval takes about 5 business days and isn't guaranteed. Unapproved testing risks provider bans, model restrictions or a **platform-wide account ban**.
- The docs **don't say** whether testing your *own* app's injection defences counts. Read literally, it does. Some safety classifiers run online, so prompts can be flagged even under Zero Data Retention.
- §6.7: OpenRouter may screen or block inputs, including automated screening for malware.
- **Consequence for this project:** DVMCP, DVLA and Promptfoo red-team suites should use a **local model (Ollama)** for the victim side, or get OpenRouter's approval first.

### Model and provider policies (for the models shortlisted in [#15](https://github.com/ZeleMate/DeepSeek-demo-implementation/issues/15))

| Model / provider | Cyber-relevant terms |
|---|---|
| **gpt-oss-20b** (OpenAI, open weights) | Apache-2.0 on the HF card. No model-specific usage policy on the card [verified, [HF](https://huggingface.co/openai/gpt-oss-20b)] |
| **OpenAI API** (Decisions API) | Usage policies prohibit malicious cyber activity. Dual-use work such as security education and human-led vulnerability finding is allowed, with enforcement on signs of malicious intent. "Trusted Access for Cyber" lowers refusals for authorised defensive work [secondary: OpenAI system card and help pages via search; the policy page returned 403] |
| **DeepSeek** (model licence) | The model licence's use restrictions have no cyber-specific clause, only a general "violates any applicable … law" ban [verified, [V3 LICENSE-MODEL](https://huggingface.co/deepseek-ai/DeepSeek-V3/blob/main/LICENSE-MODEL)]. Licence for V4.x not checked [unverified]. DeepSeek's API terms are governed by Chinese law, but OpenRouter usually routes to third-party hosts |
| **Mistral** (Nemo) | Usage Policy, effective 2026-06-11: prohibits "creating malware and exploiting vulnerabilities" and circumventing security protections or AI safety filters [verified, [policy](https://legal.mistral.ai/terms/usage-policy)] |
| **Meta Llama 4** (reference) | AUP bans malicious code and malware, and attacks that "disable, overburden, interfere with" systems, plus circumventing safety measures [verified, [AUP](https://dev.meta.ai/llama/llama4/use-policy/)] |
| **Z.ai GLM, NVIDIA Nemotron** | Not checked [unverified] |

**Refusal behaviour** of these specific models on security prompts was **not measured** [unverified]. Expect requests like "explain this CVE" or "write a Sigma rule" to pass. Expect "write working malware" or "attack host X" to be refused by some models and to breach Mistral's and Llama's policies even when not refused. Measure it with a small Promptfoo suite of **benign, defensive** prompts, not jailbreaks (see red teaming above).

## 6. Safe-by-default rules for this project

1. **Targets allowlist in code.** The harness may only reach `127.0.0.1`, `localhost` and named Docker networks of labs you started. Every other host is denied by the sandbox or permission plugin, whatever the prompt says.
2. **Bind every lab to loopback** (`-p 127.0.0.1:…`), use Docker 28 or later, and stop labs when you're done (`docker compose down`). DVWA auto-restarts.
3. **No agent on third-party platforms.** No TryHackMe or HTB login for the agent, and no eval sets or training data from their content. Practise there by hand.
4. **Prompt-injection and jailbreak work uses a local model** (Ollama) on the victim side, unless OpenRouter has approved it in writing.
5. **Defensive-first tasks** for the cheap models: CVE, ATT&CK and Sigma analysis, log triage on BOTS or OTRF data, and code review of lab apps.
6. **Don't publish weaponised artefacts.** No exploit kits, harvested credentials or reusable attack tooling in the repo (Btk. §424, Directive Art. 7). Lab writeups are fine. Platform writeups only for retired content.
7. **Human approval for any active step** (scan, exploit, write) through dsh's permission plugin. Log every tool call to the session log.
8. **Labs run isolated:** no host mounts, no secrets in lab containers, and API keys never passed into the sandbox.
9. **When unsure whether something is in scope, it isn't.** Write the scope down first (host, time, techniques) and keep it in the repo.

## Open questions and unverified items

- HTB 2026 AUP: exact wording on automation and on using its content to "test" AI.
- picoCTF's current AI or automation stance. NVD's exact rate limits.
- OpenRouter: does testing your own app's injection defences need approval? Ask `safety@openrouter.ai` if it matters.
- GLM, Nemotron and DeepSeek V4.x licence terms. Measured refusal rates of the #15 shortlist.
- OTRF licence (GPL-3.0 vs MIT). Hungary's Budapest Convention status (believed a party).
