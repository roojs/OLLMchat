<!--
  C4: streaming table placeholder — long enough to see “a table being created …”
  before the 3-line gate completes. Use a slow stream so the wait is obvious.

  build/examples/oc-test-gtkmd --stream 0 tests/markdown/repro-table-pending.md
-->

Here is some lead-in text so you can watch the stream before the table starts.

Then a wide table (long header / separator / first body lines stretch the pending window):

| Feature name with extra wording so this header cell is long | Status column also padded with description text | Notes and commentary that keep this third header wide enough |
|:-----------------------------------------------------------|:-----------------------------------------------:|------------------------------------------------------------:|
| Alpha rollout across regions with detailed checklist items | In progress — waiting on final QA sign-off steps | Owner: platform team; follow-up after the next release train |
| Beta feature flag for enterprise tenants only for now | Blocked on dependency upgrade in shared library | See tracking ticket; do not enable in production yet please |
| Gamma analytics dashboard widgets for ops and support | Done — shipped last week after design review pass | Docs updated; training scheduled for the customer success org |
| Delta backup and restore pipeline with encryption at rest | Planned for next sprint pending capacity planning | Needs security review before the implementation work begins |
| Epsilon notification fan-out for mobile and desktop clients | In progress — partial rollout to internal users | Metrics look healthy; expand cohort after another day of soak |
