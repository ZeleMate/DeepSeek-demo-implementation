# Web search: Brave Search API vs Tavily

Research for issue #9. All sources checked **2026-10-18**. Prices and limits change often, so recheck before committing money.

## Answer

For a one-user, small-budget, learning-first research assistant, **Tavily is the better first backend**. It has 1,000 free credits a month with no card, results already shaped for an LLM (snippets per source, optional cleaned page content in markdown, an optional answer), an official TS SDK (`@tavily/core`), and terms that do not forbid storing results. **Brave** is cheap and fast, and its LLM Context endpoint is a strong agent-ready option. But its API terms forbid storing or caching results beyond what the app needs to run, and it has no official TS SDK. That clashes with a harness whose job is "keep notes". Hide search behind a small `search(query)` tool interface so Brave can be added later.

## Comparison

| | Brave Search API | Tavily |
|---|---|---|
| Free tier | $5 of free credits per month per plan ("up to $20 in free calls every month" across plans) [B1] | Researcher plan: 1,000 credits per month, no credit card [T1] |
| Paid price | Search: $5 per 1,000 requests. Answers: $4 per 1,000 requests plus $5 per million tokens. Prepaid credits, no subscription [B1] | Pay as you go: $0.008 per credit. Project: $30 per month for 4,000 credits [T1] |
| Unit cost | 1 request = 1 call | Search basic, fast or ultra-fast: 1 credit. Search advanced: 2. Extract: 1 credit per 5 URLs (basic) or 2 per 5 (advanced). Research: 4 to 250 credits [T2]\[T3] |
| Rate limits | Search: 50 queries per second. Answers: 2 queries per second [B1] | Dev key: 100 requests per minute. Production key (needs a paid plan or pay as you go): 1,000 requests per minute. Crawl 100 per minute, research 20 per minute. HTTP 429 with `Retry-After` [T4] |
| Snippets | `description` plus up to 5 `extra_snippets` per result. Max 20 results per page, offset up to 9 [B2] | `content` snippet per result, `chunks_per_source` 1 to 3, `max_results` 0 to 20, relevance `score`, `published_date` [T3] |
| Extracted page content | **LLM Context** endpoint (`/res/v1/llm/context`): extracted page chunks plus source metadata, with a token budget (`maximum_number_of_tokens` 1,024 to 32,768, default 8,192; per-URL cap 512 to 8,192) [B3] | `include_raw_content` (`markdown` or `text`) on search, plus a separate Extract endpoint [T3]\[T2] |
| Generated answer or citations | Answers plan: citations and streaming, compatible with the OpenAI SDK [B1]. Summarizer tool in the MCP server [B4] | `include_answer` (`basic` or `advanced`). Each result carries `url` and `title` to cite [T3] |
| TypeScript SDK | No official SDK found. Only third-party npm wrappers such as `brave-search`, which says it is unofficial [B5] | Official `@tavily/core` (search, extract, crawl, map) [T5] |
| MCP server | `@brave/brave-search-mcp-server` (brave GitHub org, MIT license, TypeScript, stdio and HTTP). Tools: web, local, video, image, news and place search, plus LLM context and summarizer [B4] | `tavily-mcp` (tavily-ai GitHub org, MIT license). Tools: search, extract, map, crawl. Also hosted at `https://mcp.tavily.com/mcp/` [T6] |
| Storing or caching results | **Restricted.** The terms (updated 1 Sep 2026) bar you from storing, caching or building a database of search results, except temporary storage needed to run your app (§3(b)(i)). They also bar derivative works (§3(b)(ii)), require you to delete results when the agreement ends (§13(c)(ii)), and bar using results to train or evaluate models (§3(b)(xiii)). Attribution is optional [B6]. The marketing FAQ says storing needs "a plan that includes storage rights" [B1]. I could not read the price of that plan on a Brave page (see open questions) | **Not prohibited.** The terms (updated 4 May 2026) do not mention caching or ownership of outputs. You may not resell or distribute the Services (§3.2), or use outputs to build competing models (§6.6). **Tavily and its AI providers may use your inputs and outputs to train models** (§6.5, §6.7). No attribution required [T7] |
| Privacy | "Architectural ZDR" (zero data retention): queries never leave Brave. Full zero data retention on Enterprise [B1] | Queries and outputs may be kept and used for training (§6.5, §9.2) [T7] |

## What this means for own-harness

- **Cost at hobby scale:** Both are effectively free. Tavily gives 1,000 basic searches a month. Brave's $5 credit buys about 1,000 Search calls a month.
- **Fit with the agent loop:** Tavily's single call (search with snippets, optionally raw markdown) maps straight onto one tool. Brave can match it with LLM Context, but you write your own `fetch` client.
- **Fit with note-taking:** Under Brave's terms, notes that copy result text or snippets may count as storing results. Notes written in your own words, plus URLs, are safer, but this is a legal grey area, not a settled answer. Tavily's terms raise no such issue, but your queries go into their training data.
- **Rate limits:** Neither matters for one user. Tavily's dev key (100 per minute) is plenty.

## Open questions

- I could not confirm the price of Brave's storage-rights plan from a Brave page. The dashboard pricing page loads by JavaScript and returned nothing. A search result points to a "Data with Storage Rights" listing at $26 or $45 per 1,000 requests on `api-docs.search.brave.software`. It is **not verified** and may be out of date.
- Whether Brave's free credit needs a card on file was not checked.
- No numeric rate limit is published per Tavily plan, only per key type.

## Sources (all checked 2026-10-18)

- [B1] Brave Search API product and pricing page: <https://brave.com/search/api/>
- [B2] Brave Web Search docs: <https://api-dashboard.search.brave.com/app/documentation/web-search/get-started>
- [B3] Brave LLM Context docs: <https://api-dashboard.search.brave.com/documentation/services/llm-context>
- [B4] Brave MCP server: <https://github.com/brave/brave-search-mcp-server>
- [B5] Third-party npm wrapper, says it is unofficial: <https://npmjs.com/package/brave-search>
- [B6] Brave Search API Terms of Service: <https://api-dashboard.search.brave.com/terms-of-service>
- [T1] Tavily pricing: <https://www.tavily.com/pricing>
- [T2] Tavily API credits: <https://docs.tavily.com/documentation/api-credits>
- [T3] Tavily Search API reference: <https://docs.tavily.com/documentation/api-reference/endpoint/search>
- [T4] Tavily rate limits: <https://docs.tavily.com/documentation/rate-limits>
- [T5] Tavily JS SDK quick start: <https://docs.tavily.com/sdk/javascript/quick-start>
- [T6] Tavily MCP server: <https://github.com/tavily-ai/tavily-mcp>
- [T7] Tavily Terms of Service: <https://www.tavily.com/terms>
