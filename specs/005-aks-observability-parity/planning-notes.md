# Planning input: separate AKS configuration

The developer requires AKS configuration for Caretta, Tempo, and Beyla to live
in a separate folder from the Amazon/local configuration, following the existing
Loki pattern. Carry this constraint into the implementation plan; this note is
not an approved plan or authorization to implement.

The existing pattern was checked with `ls infra/azure/chart-values` and a
targeted search of the makefile. The directory listing returned:

```text
alloy.yaml
loki.yaml
otel-collector.yaml
```

The Loki installation at makefile line 192 uses
`infra/azure/chart-values/loki.yaml`; the shared installation at line 114 uses
`monitoring/chart-values/loki.yaml`. For example, the added tools' AKS values
can follow this separation in the existing Azure directory. Exact new files
will be established during planning.

The spec captures the independent settings requirement as FR-008. Existing
Amazon/local settings must remain unchanged under FR-007 and issue #109.

The developer also requires the latest versions of Caretta, Tempo, and Beyla
for AKS. Interpret latest as the latest stable application releases available
at planning-time verification, not prereleases or a floating version reference.
Verify application releases and the chart versions that package them separately
against their actual release sources. Record the date, commands, actual output,
and exact pins in the planning evidence. Do not assume the latest chart contains
the latest application release. Preserve Amazon/local version pins.

No release numbers have been selected or verified yet. Any incompatibility
between the latest stable releases and AKS must be raised with the developer
before choosing an older release. The spec captures this requirement as FR-009.

## Additional developer requirements

The developer requires idempotent setup, integration into `make setup-aks`,
and an update to the existing `instructions.md`. These are captured in
FR-010–FR-012. During planning, include verification that two successive runs
with unchanged settings succeed without creating duplicate installations and
leave the three added capabilities usable.

Source checks found the existing integration points:

```text
213:setup-aks:
219:	$(MAKE) setup-aks-o11y
```

The command already includes monitoring in its ordered deployment sequence.
Extend that integration while preserving its ordering and optional load
generation behavior.

There is no root-level `instructions.md`. A filename search and `ls` found:

```text
specs/002-azure-observability-stack/instructions.md
```

This is the existing Azure deployment guide referenced by the makefile's
setup-aks comment, and is the document to update during implementation.
