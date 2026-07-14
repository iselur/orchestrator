I found three blocking defects. The collector and golden-isolation designs are otherwise internally coherent.

### Blocking findings

1. **The dispatch capture is still on the dispatch critical path.**  
   `P2-02` performs serialization, socket acquisition/reuse, and `sendmsg`/`sendto` synchronously between dispatch transitions. Most clearly, the concurrency-acquired emission occurs while the task owns its scheduler slot but before subsequent dispatch work proceeds. `SOCK_NONBLOCK` prevents waiting for journald buffer space; it does not remove the emitter’s CPU work, socket setup, page faults, exception handling, or syscall completion from the critical path.

   Cancellation also exposes an irreconcilable requirement: swallowing cancellation inside the emitter changes dispatch cancellation behavior, while propagating it lets measurement abort dispatch. The proposed fault tests cannot prove that arbitrary cancellation leaves behavior unchanged.

   Thus the design establishes bounded, fail-open instrumentation, but not the stop-rule’s stronger condition that measurement stay off the dispatch critical path.

2. **The implementation order retains a controller-attestation dependency cycle.**  
   `P2-01` and `P2-03` must positively validate attested evaluation promotion using the complete controller-attestation source set and closed `eval/controller-attestation.schema.json`. That schema is not created until `P2-06`, and neither earlier spec is allowed to add it:

   - `P2-01` requires attested-evaluation offline fixtures.
   - `P2-03` requires promotion with a valid `P2-06` attestation fixture.
   - `P2-06` later creates the authoritative schema and producer.

   A temporary or embedded anticipatory schema would not be the committed, digest-bound schema required by §§4.1 and 4.6. Therefore the claimed `P2-01 → P2-05 → P2-03 → P2-02 → … → P2-06` acceptance sequence cannot pass as written. The schema and immutable positive fixtures must move into an earlier contract spec, or positive promotion acceptance must be deferred entirely to `P2-06`.

3. **The statistical contract still permits a mechanically consistent but dishonest direction.**  
   The contract may choose the direction-statistic computation and `positive_favors` orientation, but nothing binds those choices to a trusted canonical definition for the metric. Nor must the statistic be antisymmetric under swapping baseline and candidate.

   A valid predeclared contract could therefore use `abs(candidate - baseline)` or invert the normal orientation and always derive `candidate_favorable`. Recomputing the result, freezing the contract before invocation, and generating prose from the recomputed enum would all succeed—the dishonesty is inside the accepted contract.

   Direction-capable metrics need a trusted metric-definition registry or equivalent semantic constraints, including an arm-swap invariant: swapping arms must negate the direction statistic, or preserve zero, and reverse the favorable outcome. Contract validation should reject arm-label-dependent or non-antisymmetric directional transformations.

### Other requested checks

- **Collector integrity:** Pass. Source-set and implementation binding, deterministic identities, collision sealing, explicit errors, exact-head checkpoints, preserved damaged generations, and idempotent recollection provide coherent protection against accidental fabrication, coercion, and silent omission.
- **Golden isolation:** Pass. Exact object closure, metadata scanning, opaque runtime identities, D5 isolation for both roles, absent production mounts/remotes/credentials, controller-side hidden checks, and pre-invocation canaries form a coherent containment design.
- **Advisory:** The document has two frontmatter blocks, with revision 5 parsed as the authoritative header while the body claims revision 6. Remove the stale header before authorization.

VERDICT: BLOCK
