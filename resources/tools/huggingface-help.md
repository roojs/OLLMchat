# Hugging Face Hub tool help (system slot unused)
---
HUGGING FACE HUB TOOL
---
Host memory (VRAM or unified): {vram_limit}
---

MUST — CALL HELP WHEN YOU DO NOT HAVE THIS MANIFEST
  On every turn that uses this tool: if this full help text is NOT already in your
  current context (including follow-up turns after a conversation summary), call
  {"help": true} BEFORE any search, detail, or download. A summary remnant or a
  vague recollection of these rules is NOT enough — re-fetch help, then continue.
  Do not skip help because you called it earlier in the session.

WHEN THE USER ASKS FOR A MODEL
  If the user wants to download, find, or install a GGUF from Hugging Face, you do
  the Hub pipeline with this tool: help → search → detail → download. Do NOT use
  run_command, wget, curl, huggingface-cli, or any other shell or CLI to fetch Hub
  files — those paths are wrong here and will not integrate with the app
  (permissions, activity bar, install layout). Do NOT tell the user to download
  manually or run commands themselves. Call action "download" on this tool; the
  user approves in-app and progress appears in the activity bar.

  Discovery fallback: Hub search is keyword-only and often misses repos. You MAY
  use google_search (or web_search) to find the correct Hub author/name, page
  title, or model family spelling — then return to this tool with "detail" /
  "download" on the verified model_ref. Do NOT use google_search to fetch GGUF
  binaries. Do NOT use web_fetch to download model files from Hub CDN URLs.

PRIMARY STRATEGY: MULTI-TOKEN PREDICTION (MTP) SPECULATIVE INFERENCE
To maximize performance, prioritize downloading models with built-in MTP heads
(or explicit Draft-Model companions). This speeds up token generation by up to 2x
by predicting multiple tokens per forward pass.

CRITICAL HARDWARE BUDGETING RULES:
  1. SINGLE-FILE MTP MODELS: Highly recommended. These feature integrated self-speculation
     heads (e.g., Unsloth MTP GGUF series). They use only ~1-2% more VRAM than basic weights,
     making them incredibly memory efficient.
  2. TRADITIONAL DRAFT PAIRS: If downloading a separate draft model, the combined file
     sizes of BOTH the target and draft models must fit entirely inside the Memory Limit
     noted above, leaving a 2-4GB safety gap for context allocation.
  3. QUANTIZATION CHOICE: Scale quantization down (e.g., Q4_K_M or IQ3 variants) to guarantee
     the file sizes safely accommodate the host machine's memory boundaries.

---
PARAMETER REFERENCE
---
  help       {boolean}  Set true to retrieve this manifest. Call whenever this
                         help text is not already in the current turn context
                         (every new Hub workflow, including follow-ups).
  action     {string}   Required on operational calls. One of:
                         • "search"  — find GGUF repos matching query
                         • "detail"  — fetch file tree and sizes for one model_ref
                         • "download" — fetch specific files from model_ref
  query      {string}   Required for action "search". Short keyword string passed
                         to Hub GET /api/models?search=…. NOT semantic or fuzzy:
                         every word must match repo metadata; extra words often yield
                         zero hits. Use 3–5 tokens (e.g. "Gemma 4 MTP GGUF").
  model_ref  {string}   Required for "detail" and "download". Hub repo id "author/name".
  files      {array}   Required for "download". Array of strings — exact sibling
                         filenames from detail output (e.g. ["model.gguf"]).
                         Include every shard (.gguf-split-N) when the model is split.

---
1. HUB SEARCH (KEYWORD ONLY — NOT FUZZY OR SEMANTIC)
---
Hub search matches repo id, card text, and tags by literal keywords. It does NOT
understand synonyms, "speculative inference", or your intent. Adding jargon
often returns ZERO results even when matching repos exist.

  DO:
    • Short queries: model family + size/variant + MTP + GGUF (about 3–5 words)
    • Working examples: "Gemma 4 MTP GGUF", "Gemma MTP GGUF", "qwen mtp gguf"
    • Zero hits → REMOVE words and retry; do not pile on more synonyms
    • Separate searches per family (gemma, qwen, llama) — not one long mash-up
    • User named a repo (author/name) → skip search; call "detail" on that ref

  DO NOT:
    • Long synonym dumps: "specul draft unsloth llava llama …" in one query
    • Treat zero hits as "model does not exist" — the query was probably too broad
    • Invent version numbers the user did not mention
    • Stick forever on Hub search alone when names are unclear — google_search
      (or web_search) for author/repo discovery, then "detail" on this tool

---
2. SEARCH EXAMPLES FOR MTP
---
  • {"action": "search", "query": "Gemma 4 MTP GGUF"}
  • {"action": "search", "query": "qwen mtp gguf"}
  • {"action": "search", "query": "llama mtp gguf"}

---
3. OPERATION PIPELINE
---
  Step H: If this help text is not already in the current turn, call help:true first.
  Step 0 (optional): If Hub "search" keeps missing the repo the user means,
          use google_search / web_search only to discover author/name or
          spelling, then jump to Step B with that model_ref.
  Step A: Call "search" with a SHORT keyword query (see section 1).
          Search returns downloadable repos only (gated and private are omitted).
          Call "detail" on a chosen model_ref for file sizes.
  Step B: Call "detail" using the exact "model_ref" repo string to fetch its file tree.
  Step C: Review file sizes under the "siblings" list to calculate memory compliance.
  Step D: Execute "download" with precise filenames in the "files" array.
          Never substitute run_command or shell downloads for this step.
          You will be asked to confirm the download (file list and total size)
          before it starts. Progress appears in the activity bar.
          (Always include ALL related .gguf-split-x parts if the model is sharded).
