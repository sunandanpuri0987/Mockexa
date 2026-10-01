from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class Company:
    id: str
    name: str
    focus: str


@dataclass(frozen=True)
class CompanyQuestion:
    id: str
    company_id: str
    prompt: str
    category: str
    role: str
    round: str
    year: int
    difficulty: int
    source_title: str
    source_url: str
    source_kind: str
    focus_points: tuple[str, ...]
    answer_outline: str

    def public_dict(self, *, include_answer: bool = False) -> dict:
        value = asdict(self)
        value["focus_points"] = list(self.focus_points)
        if not include_answer:
            value.pop("answer_outline", None)
            value.pop("focus_points", None)
        return value


COMPANIES = (
    Company("google", "Google", "Algorithms, scalable systems, structured problem solving"),
    Company("amazon", "Amazon", "DSA, leadership principles, ownership and system design"),
    Company("microsoft", "Microsoft", "CS fundamentals, clean code, collaboration and design"),
    Company("apple", "Apple", "Product quality, systems, reliability and deep technical reasoning"),
    Company("meta", "Meta", "Fast coding, graphs, product systems and behavioral impact"),
    Company("adobe", "Adobe", "Programming fundamentals, Java, testing and product engineering"),
    Company("flipkart", "Flipkart", "DSA, e-commerce scale, low-level design and problem solving"),
    Company("atlassian", "Atlassian", "Coding, collaboration systems, design and values"),
    Company("accenture", "Accenture", "Core programming, CS fundamentals, projects and communication"),
    Company("deloitte", "Deloitte", "Programming, consulting scenarios, OOP and problem solving"),
    Company("jpmorgan", "JPMorgan", "Java, DSA, reliability, finance systems and teamwork"),
    Company("goldman_sachs", "Goldman Sachs", "DSA, core Java, systems, mathematics and design"),
)


def _q(company: str, slug: str, prompt: str, category: str, role: str, round_name: str,
       year: int, difficulty: int, source_title: str, source_url: str,
       focus: tuple[str, ...], outline: str, source_kind: str = "candidate_report") -> CompanyQuestion:
    return CompanyQuestion(
        id=f"{company}-{slug}", company_id=company, prompt=prompt, category=category,
        role=role, round=round_name, year=year, difficulty=difficulty,
        source_title=source_title, source_url=source_url, source_kind=source_kind,
        focus_points=focus, answer_outline=outline,
    )


GOOGLE_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/software-engineer-interview-at-google-hyderabad/"
AMAZON_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/amazon-interview-experience-for-sde-i-off-campus-2025/"
MICROSOFT_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/microsoft-interview-experience-for-software-engineer-1-year-experienced/"
APPLE_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/apple-interview-experience/"
META_SOURCE = "https://www.geeksforgeeks.org/dsa/facebookmeta-sde-sheet-interview-questions-and-answers/"
ADOBE_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/adobe-interview-set-10-software-engineer/"
FLIPKART_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/flipkart-interview-experience-for-software-developer-intern/"
ATLASSIAN_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/atlassian-interview-experience-on-campus-fte/"
ACCENTURE_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/accenture-interview-experience-for-software-engineer/"
DELOITTE_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/deloitte-software-developer-interview-experience/"
JPMORGAN_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/jp-morgan-chase-co-jpmc-interview-experience-full-time-software-engineer/"
GOLDMAN_SOURCE = "https://www.geeksforgeeks.org/interview-experiences/goldman-sachs-interview-experience-2025-for-compliance-software-engineer/"


# Prompts are concise paraphrases of the linked reports. Keeping the source on
# every record makes provenance inspectable and avoids presenting crowdsourced
# reports as an official company syllabus.
QUESTIONS = (
    _q("google", "palindrome-cut", "Given two equal-length strings, choose a shared cut so the prefix of the first and suffix of the second form a palindrome. Explain an efficient approach and extensions for unrestricted cuts.", "DSA", "Software Engineer", "Phone screen", 2025, 4, "Software Engineer Interview at Google, Hyderabad", GOOGLE_SOURCE, ("two pointers", "palindrome", "prefix suffix", "complexity"), "Compare mirrored characters around candidate boundaries; discuss preprocessing or hashes for many cuts and state complexity."),
    _q("google", "sorting-complexity", "Compare the best, average, and worst-case complexity of common sorting algorithms and explain when you would choose each.", "Technical", "Software Engineer", "Recruiter technical screen", 2025, 3, "Software Engineer Interview at Google, Hyderabad", GOOGLE_SOURCE, ("time complexity", "space complexity", "stability", "input characteristics"), "Cover quicksort, mergesort and heapsort trade-offs, including stability, memory and adversarial input."),
    _q("google", "global-messaging", "Design a globally scalable real-time messaging service. Walk through APIs, storage, delivery guarantees, ordering, presence and failure handling.", "System Design", "Software Engineer", "System design", 2024, 5, "Google Interview Experience for Software Engineer", "https://www.geeksforgeeks.org/interview-experiences/google-interview-experience-for-software-engineer-6/", ("websocket", "message queue", "partitioning", "delivery semantics", "observability"), "Define requirements first, then cover gateways, durable queues, partitioned storage, fan-out, ordering keys, retries and monitoring."),
    _q("google", "conflict", "Tell me about a high-pressure team conflict you helped resolve. What trade-off did you make and what measurable result followed?", "Behavioral", "Software Engineer", "Googliness", 2024, 3, "Google Interview Experience for Software Engineer", "https://www.geeksforgeeks.org/interview-experiences/google-interview-experience-for-software-engineer-6/", ("situation", "ownership", "collaboration", "result", "reflection"), "Use STAR, make your own actions explicit, quantify the result and explain what you learned."),

    _q("amazon", "complete-subarrays", "Count subarrays that contain every distinct value present in the full array. Start with brute force, then optimize and dry-run your solution.", "DSA", "SDE-I", "Technical", 2025, 4, "Amazon Interview Experience for SDE-I (Off-Campus 2025)", AMAZON_SOURCE, ("sliding window", "frequency map", "distinct count", "complexity"), "Use a two-pointer window and frequency map; count valid extensions once all distinct values are present."),
    _q("amazon", "merge-cost", "Repeatedly merge two values, paying their sum each time. Find the minimum possible total cost and justify the data structure.", "DSA", "SDE-I", "Technical", 2025, 3, "Amazon Interview Experience for SDE-I (Off-Campus 2025)", AMAZON_SOURCE, ("min heap", "greedy", "optimal merge", "complexity"), "Always merge the two smallest values using a min-heap; justify the greedy choice and O(n log n) time."),
    _q("amazon", "dive-deep", "Describe the last time you had to dive deeply into a production bug. How did you isolate the cause and prevent recurrence?", "Behavioral", "SDE-I", "Bar raiser", 2025, 3, "Amazon Interview Experience for SDE-I (Off-Campus 2025)", AMAZON_SOURCE, ("ownership", "data", "root cause", "prevention", "impact"), "Use STAR and show logs/metrics, hypothesis testing, root cause, remediation and a measurable prevention mechanism."),
    _q("amazon", "negative-feedback", "Tell me about difficult feedback you received. What did you change, and what evidence showed improvement?", "Behavioral", "SDE-I", "Bar raiser", 2025, 2, "Amazon Interview Experience for SDE-I (Off-Campus 2025)", AMAZON_SOURCE, ("self awareness", "action", "feedback loop", "measurable result"), "Own the gap without defensiveness, describe specific behavior change and provide evidence of sustained improvement."),

    _q("microsoft", "reverse-list", "Reverse a singly linked list in place. Explain invariants, edge cases, and time/space complexity.", "DSA", "Software Engineer", "Technical 1", 2025, 2, "Microsoft Interview Experience — 1 Year Experienced", MICROSOFT_SOURCE, ("prev current next", "pointer update", "null head", "complexity"), "Iterate with previous/current/next pointers in O(n) time and O(1) extra space; cover empty and single-node lists."),
    _q("microsoft", "binary-linked", "Two binary numbers are stored as linked lists. Add them and return the result as a linked list.", "DSA", "Software Engineer", "Technical 2", 2025, 3, "Microsoft Interview Experience — 1 Year Experienced", MICROSOFT_SOURCE, ("carry", "linked list", "digit traversal", "edge cases"), "Align traversal direction, maintain carry, create result nodes and handle a final carry and unequal lengths."),
    _q("microsoft", "producer-consumer", "Explain and implement a thread-safe producer-consumer queue. Discuss mutual exclusion, signalling, shutdown and back-pressure.", "Technical", "Software Engineer", "Technical 2", 2025, 4, "Microsoft Interview Experience — 1 Year Experienced", MICROSOFT_SOURCE, ("mutex", "condition variable", "bounded queue", "deadlock", "shutdown"), "Protect queue state with a lock, use not-empty/not-full conditions, loop on predicates and design explicit shutdown."),
    _q("microsoft", "peer-feedback", "Tell me about a time you received constructive feedback from a peer and changed your approach.", "Behavioral", "Software Engineer", "Manager", 2025, 2, "Microsoft Interview Experience — 1 Year Experienced", MICROSOFT_SOURCE, ("feedback", "collaboration", "action", "result"), "Give a specific STAR story showing listening, a concrete adjustment and improved team or product outcome."),

    _q("apple", "josephus", "Solve the Josephus elimination problem and derive an analytical or recurrence-based solution.", "DSA", "Software Engineer", "Coding", 2024, 4, "Apple Interview Experience", APPLE_SOURCE, ("recurrence", "modulo", "base case", "complexity"), "Use J(1)=0 and J(n)=(J(n-1)+k) mod n, then convert indexing if needed."),
    _q("apple", "leaderboard", "Design a game leaderboard that serves global and regional top rankings with low latency and high availability.", "System Design", "Software Engineer", "System design", 2024, 5, "Apple Interview Experience", APPLE_SOURCE, ("sorted set", "partitioning", "cache", "consistency", "regional ranking"), "Clarify ranking rules; discuss event ingestion, regional partitions, sorted indexes, caches, reconciliation and abuse controls."),
    _q("apple", "dns", "Explain what happens after entering a URL in a browser, then design a resilient DNS-like lookup service.", "System Design", "Software Engineer", "System design", 2024, 5, "Apple Interview Experience", APPLE_SOURCE, ("dns resolution", "caching", "ttl", "replication", "failure handling"), "Cover browser/OS caches, recursive resolution, TCP/TLS/HTTP, then authoritative storage, TTLs, replication and failover."),
    _q("apple", "project-scale", "Choose one project from your resume and explain how you would redesign it for 100 times the traffic.", "Behavioral", "Software Engineer", "HR/Projects", 2024, 3, "Apple Interview Experience", APPLE_SOURCE, ("baseline", "bottleneck", "scaling", "trade-off", "measurement"), "State current constraints, identify bottlenecks from measurements and prioritize scaling changes with trade-offs."),

    _q("meta", "top-k", "Given an integer array, return the k most frequent values and analyze alternatives for different constraints.", "DSA", "Software Engineer", "Coding", 2026, 3, "Facebook (Meta) SDE Sheet", META_SOURCE, ("frequency map", "heap", "bucket sort", "complexity"), "Count frequencies, then use a size-k heap or frequency buckets; compare O(n log k) and O(n) trade-offs.", "frequently_asked_collection"),
    _q("meta", "rotate-matrix", "Rotate an n by n matrix 90 degrees in place and prove why your index transformations are correct.", "DSA", "Software Engineer", "Coding", 2026, 3, "Facebook (Meta) SDE Sheet", META_SOURCE, ("transpose", "reverse", "in place", "index mapping"), "Transpose then reverse each row, or rotate layers; explain O(n²) time and O(1) extra space.", "frequently_asked_collection"),
    _q("meta", "news-feed", "Design a social news feed with ranking, pagination, celebrity accounts and freshness requirements.", "System Design", "Software Engineer", "System design", 2026, 5, "Facebook (Meta) SDE Sheet", META_SOURCE, ("fanout", "ranking", "cache", "pagination", "hot users"), "Define SLAs and ranking inputs; compare fan-out-on-write/read, hybrid celebrity handling, cursor pagination and cache invalidation.", "frequently_asked_collection"),
    _q("meta", "impact", "Describe a decision where you moved quickly with incomplete information. How did you manage risk and measure impact?", "Behavioral", "Software Engineer", "Behavioral", 2026, 3, "Facebook (Meta) SDE Sheet", META_SOURCE, ("decision", "risk", "experiment", "impact", "learning"), "Explain the reversible decision, guardrails, success metrics, outcome and what new evidence changed.", "frequently_asked_collection"),

    _q("adobe", "binary-decimal", "Convert a binary value to decimal without relying on a library conversion call. Handle invalid input and overflow.", "DSA", "Software Engineer", "Technical", 2025, 2, "Adobe Interview — Software Engineer", ADOBE_SOURCE, ("positional notation", "validation", "overflow", "complexity"), "Scan digits, validate 0/1, accumulate value=value*2+digit and guard overflow."),
    _q("adobe", "java-sync", "Compare synchronized methods and synchronized blocks in Java, including lock scope and contention.", "Technical", "Software Engineer", "Java screening", 2025, 3, "Adobe Interview — Software Engineer", ADOBE_SOURCE, ("monitor", "lock scope", "contention", "thread safety"), "Explain instance/class monitors, smaller critical sections, visibility guarantees and avoiding nested-lock deadlocks."),
    _q("adobe", "attachment-tests", "An email attachment fails to open. Design a focused test plan that isolates client, file, network and permission causes.", "Technical", "Software Engineer", "Technical", 2025, 3, "Adobe Interview — Software Engineer", ADOBE_SOURCE, ("reproduction", "test matrix", "logs", "file integrity", "permissions"), "Build a minimal reproduction matrix, verify MIME/content/hash, inspect logs, isolate layers and add regression tests."),
    _q("adobe", "toughest-bug", "Walk through the toughest bug you fixed, including the misleading signals and the permanent corrective action.", "Behavioral", "Software Engineer", "Technical", 2025, 3, "Adobe Interview — Software Engineer", ADOBE_SOURCE, ("debugging", "root cause", "ownership", "prevention", "impact"), "Use a concrete incident: symptoms, hypotheses, evidence, root cause, fix, validation and prevention."),

    _q("flipkart", "substring-count", "Count case-insensitive occurrences of a pattern in a large text. Discuss overlapping matches and faster alternatives.", "DSA", "Software Engineer Intern", "Coding test", 2025, 3, "Flipkart Interview Experience — Software Developer Intern", FLIPKART_SOURCE, ("string matching", "overlap", "kmp", "rolling hash"), "Clarify overlapping behavior; present linear scanning and KMP/rolling-hash options with complexity."),
    _q("flipkart", "container-water", "Given vertical line heights, find the maximum water container and justify the two-pointer greedy move.", "DSA", "Software Engineer Intern", "Technical", 2025, 3, "Flipkart Interview Experience — Software Developer Intern", FLIPKART_SOURCE, ("two pointers", "area", "greedy proof", "complexity"), "Start at both ends, update area and move the shorter wall; explain why moving the taller cannot improve the bound."),
    _q("flipkart", "autocomplete", "Design the backend and data structure for low-latency autocomplete with popularity ranking and typo tolerance.", "System Design", "SDE-I", "Low-level design", 2024, 5, "Flipkart Interview Experience for SDE", "https://www.geeksforgeeks.org/interview-experiences/flipkart-interview-experience-for-sde-5/", ("trie", "ranking", "cache", "typo tolerance", "updates"), "Discuss trie/prefix index, top-k caching, offline ranking, incremental updates, fuzzy matching and latency metrics."),
    _q("flipkart", "sorted-list", "How would you optimize search and insertion in a sorted linked structure while controlling additional memory?", "Technical", "Software Engineer Intern", "Technical", 2025, 4, "Flipkart Interview Experience — Software Developer Intern", FLIPKART_SOURCE, ("skip list", "indexing", "trade-off", "complexity"), "Introduce sparse express links or a skip list; explain probabilistic O(log n) operations and memory trade-offs."),

    _q("atlassian", "decode-number", "A numeric string is encoded through shifted rows with placeholder characters. Recover the original sequence and validate malformed input.", "DSA", "Software Engineer", "Online assessment", 2025, 4, "Atlassian Interview Experience — On-Campus FTE", ATLASSIAN_SOURCE, ("string parsing", "index mapping", "validation", "complexity"), "Derive the row/column layout from k, reconstruct characters by mapped positions and reject inconsistent lengths."),
    _q("atlassian", "prime-parts", "Split a digit string into the minimum number of prime-valued parts within a fixed range.", "DSA", "Software Engineer", "Online assessment", 2025, 4, "Atlassian Interview Experience — On-Campus FTE", ATLASSIAN_SOURCE, ("dynamic programming", "prime lookup", "substring", "leading zero"), "Precompute primes, use dp[i] for minimum parts through index i, test bounded substrings and reject leading zeroes."),
    _q("atlassian", "chat-system", "Explain how you would design a WhatsApp-like real-time chat system, including protocol choices and push notifications.", "System Design", "Software Engineer", "Technical", 2025, 5, "Atlassian Interview Experience — On-Campus FTE", ATLASSIAN_SOURCE, ("persistent connection", "message queue", "push notification", "delivery receipt", "storage"), "Cover connection gateways, durable queues, offline storage, device sync, delivery states, encryption boundaries and push fallback."),
    _q("atlassian", "teamwork", "Describe a disagreement about a technical design and how you helped the team reach a decision.", "Behavioral", "Software Engineer", "Values/HR", 2025, 3, "Atlassian Interview Experience — On-Campus FTE", ATLASSIAN_SOURCE, ("collaboration", "evidence", "trade-off", "decision", "result"), "Show respectful challenge, decision criteria, an experiment or data, commitment after decision and outcome."),

    _q("accenture", "hashmap", "Explain how a hash map works, then outline an implementation with collisions, resizing and deletion.", "Technical", "Software Engineer", "Technical", 2025, 3, "Accenture Interview Experience — Software Engineer", ACCENTURE_SOURCE, ("hash function", "collision", "load factor", "resize", "deletion"), "Use bucket indexing with chaining/open addressing, define equality, resizing threshold and deletion semantics."),
    _q("accenture", "stack", "Implement a stack and explain how you would make it safe for concurrent callers.", "DSA", "Software Engineer", "Technical", 2025, 2, "Accenture Interview Experience — Software Engineer", ACCENTURE_SOURCE, ("lifo", "push pop", "underflow", "synchronization"), "Provide push/pop/peek and underflow handling; add locking or a lock-free strategy if concurrency is required."),
    _q("accenture", "reverse-list", "Reverse a linked list iteratively and recursively, comparing stack usage and failure cases.", "DSA", "Software Engineer", "Technical", 2025, 2, "Accenture Interview Experience — Software Engineer", ACCENTURE_SOURCE, ("pointer update", "recursion", "stack space", "edge cases"), "Iterative is O(n)/O(1); recursive is O(n)/O(n) call stack. Cover empty and single-node inputs."),
    _q("accenture", "why-hire", "Why should this team hire you? Connect your evidence to the role rather than listing generic strengths.", "Behavioral", "Software Engineer", "HR", 2025, 2, "Accenture Interview Experience — Software Engineer", ACCENTURE_SOURCE, ("role fit", "evidence", "impact", "learning"), "Map two or three job needs to concrete achievements, working style and a credible learning plan."),

    _q("deloitte", "binary-search", "Implement binary search and explain loop invariants, boundary choices and overflow-safe midpoint calculation.", "DSA", "Software Developer", "Technical screening", 2024, 2, "Deloitte Software Developer Interview Experience", DELOITTE_SOURCE, ("sorted input", "loop invariant", "boundaries", "logarithmic"), "Define inclusive or half-open bounds consistently, use safe midpoint and prove O(log n) termination."),
    _q("deloitte", "oop-functional", "Compare object-oriented and functional programming, including state, composition, testing and suitable use cases.", "Technical", "Software Developer", "Technical screening", 2024, 3, "Deloitte Software Developer Interview Experience", DELOITTE_SOURCE, ("encapsulation", "immutability", "composition", "side effects", "trade-off"), "Contrast objects/state with pure functions/immutability and explain where a hybrid approach is useful."),
    _q("deloitte", "banking-classes", "Design a class model for customers, accounts and transactions in a banking system.", "System Design", "Software Developer", "Coding challenge", 2024, 4, "Deloitte Software Developer Interview Experience", DELOITTE_SOURCE, ("entities", "invariants", "transaction", "audit", "security"), "Define aggregates and services, preserve balance invariants, make transfers atomic and include authorization/auditability."),
    _q("deloitte", "debug-team", "Explain how you debug a difficult issue collaboratively without creating duplicated work or blame.", "Behavioral", "Software Developer", "Technical", 2024, 3, "Deloitte Software Developer Interview Experience", DELOITTE_SOURCE, ("triage", "communication", "hypothesis", "ownership", "retrospective"), "Describe incident roles, shared evidence, hypothesis ownership, frequent updates, validation and blameless follow-up."),

    _q("jpmorgan", "coin-change", "Using coin values 1, 3 and 6, find the minimum coins needed for a target sum and generalize the solution.", "DSA", "Software Engineer", "HireVue", 2025, 3, "JPMorgan Full-Time Software Engineer Interview", JPMORGAN_SOURCE, ("dynamic programming", "state transition", "base case", "complexity"), "Use dp[x]=1+min(dp[x-c]) with dp[0]=0; discuss unreachable states and O(amount*coins)."),
    _q("jpmorgan", "reverse-add", "Repeatedly add an integer to its digit reversal until a palindrome appears. Return the result and iteration count safely.", "DSA", "Software Engineer", "HireVue", 2025, 2, "JPMorgan Full-Time Software Engineer Interview", JPMORGAN_SOURCE, ("palindrome", "iteration", "overflow", "termination policy"), "Reverse digits, add, test palindrome, and define overflow/iteration limits because convergence is not guaranteed for every input."),
    _q("jpmorgan", "notepad", "Design a notepad-like application supporting edit history, undo/redo, persistence and large documents.", "System Design", "Software Engineer", "Technical", 2024, 4, "JPMorgan Interview Experience", "https://www.geeksforgeeks.org/interview-experiences/jpmorgan-interview-experience/", ("command pattern", "undo redo", "piece table", "persistence", "autosave"), "Use command history for undo/redo, a rope/piece table for large text, snapshots plus journal and crash-safe autosave."),
    _q("jpmorgan", "successful-team", "Describe a successful team you contributed to, your specific role and the hardest collaboration challenge.", "Behavioral", "Software Engineer", "HireVue", 2025, 2, "JPMorgan Full-Time Software Engineer Interview", JPMORGAN_SOURCE, ("role", "collaboration", "challenge", "action", "result"), "Use STAR and distinguish team outcome from your contribution; include conflict handling and evidence."),

    _q("goldman_sachs", "recurring-decimal", "Convert a fraction to decimal notation and place repeating digits inside parentheses.", "DSA", "Software Engineer", "CoderPad", 2025, 4, "Goldman Sachs Interview — Experienced Software Engineer", "https://www.geeksforgeeks.org/interview-experiences/goldman-sachs-interview-experience-software-engineer-experienced/", ("remainder map", "long division", "cycle detection", "sign"), "Track each remainder's output index during long division; a repeated remainder marks the recurring segment."),
    _q("goldman_sachs", "deque", "Implement a double-ended queue without using collection classes, including resizing and edge cases.", "DSA", "Software Engineer", "CoderPad", 2025, 4, "Goldman Sachs Interview — Experienced Software Engineer", "https://www.geeksforgeeks.org/interview-experiences/goldman-sachs-interview-experience-software-engineer-experienced/", ("circular buffer", "head tail", "resize", "amortized complexity"), "Use a circular dynamic array with head, size and capacity; map logical indexes and double capacity when full."),
    _q("goldman_sachs", "utility-payments", "Design a utility-payment platform covering bill discovery, payment execution, idempotency, security and reconciliation.", "System Design", "Software Engineer", "Software engineering", 2025, 5, "Goldman Sachs Compliance Software Engineer Interview", GOLDMAN_SOURCE, ("idempotency", "payment state machine", "ledger", "security", "reconciliation"), "Define APIs and state transitions, idempotency keys, immutable ledger, provider adapters, authentication, retries and reconciliation."),
    _q("goldman_sachs", "production-quality", "Explain a design pattern you used in production and the trade-off it introduced.", "Behavioral", "Software Engineer", "Software engineering", 2025, 3, "Goldman Sachs Compliance Software Engineer Interview", GOLDMAN_SOURCE, ("context", "pattern", "trade-off", "testing", "outcome"), "Name the concrete problem first, show why the pattern fit, what complexity it added and how you verified the result."),
)


COMPANY_BY_ID = {company.id: company for company in COMPANIES}
QUESTIONS_BY_ID = {question.id: question for question in QUESTIONS}

