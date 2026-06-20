#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================================
# THE ALPHABET COMPLETENESS FORCING-FUNCTION
# (CATALOG REFLECTION applied to the pleme-lib HELM primitive vocabulary).
# ============================================================================
#
# "We have the entire alphabet" is not a claim — it is a property the substrate
# PROVES. pleme-lib's named templates (`{{- define "pleme-lib.<name>" }}`) ARE
# the Helm alphabet. Every letter must be one of:
#
#   (a) DIRECT-COVERED  — exercised by a helm-unittest assertion: a fixture
#       harness (tests/_fixtures/*/templates/) OR a consumer chart with a
#       tests/<chart>/ suite `include`s it, directly or TRANSITIVELY (a define
#       included by a covered define is covered — that is exactly what a
#       rendered assertion exercises).
#
#   (b) FAMILY-COVERED  — a member of a value-dispatched FAMILY that the
#       compliance corpus covers. The overlay.* and compliance.* surfaces are
#       NEVER named by a literal `include`; they are dispatched dynamically via
#       `include (printf "pleme-lib.overlay.%s.%s" $regime $surface)`. The
#       compliance corpus (tests/pleme-microservice/compliance_*) renders
#       pleme-microservice once per regime for all 14 regimes, which drives the
#       dispatch chain across every overlay surface + the compliance.* helpers
#       the overlays delegate to. We credit these as covered GROUPS — and we
#       PROVE the predicate is real by asserting the corpus actually sets every
#       registered regime (see `verify_family_corpus`).
#
#   (c) WAIVED — a tracked debt with a reason. The goal is to SHRINK this list.
#       Every entry is a hole in the alphabet's proof.
#
# The moment a new define lands that is none of the above, this check goes red,
# so the alphabet can only ever grow with its proof intact. Run via:
#
#     ruby tests/alphabet_completeness.rb        (from repo root)
#     nix run .#"lib:alphabet"
#
# Model: pangea-architectures/spec/architectures/alphabet_completeness_spec.rb.

require 'set'

REPO_ROOT = File.expand_path('..', __dir__)
Dir.chdir(REPO_ROOT)

LIB_TEMPLATES = 'charts/pleme-lib/templates'

# The 14 compliance regimes the corpus must set for FAMILY credit to be honest.
REGIMES = %w[
  fedramp-low fedramp-moderate fedramp-high
  airgap-consumer airgap-registry-mirror mirror
  supplychain fips
  dod-il2 dod-il4 dod-il5 dod-il6
  hipaa cmmc-l3
].freeze

# WAIVERS — letters with no assertion yet, each a TRACKED DEBT with a reason.
# The goal is an EMPTY list. Aliases (crossplaneMRAP / crossplaneXRD) point at a
# COVERED canonical define; the rest are primitives awaiting a bare-fixture
# harness + suite (the rate-limit-worker.* family was the first burndown).
WAIVED = {
  'pleme-lib.alerts' => 'generic PrometheusRule emitter; bare-fixture harness pending',
  'pleme-lib.breathability' => 'KEDA ScaledObject emitter; bare-fixture harness pending',
  'pleme-lib.bytes' => 'byte-quantity formatter helper; unit-assert harness pending',
  'pleme-lib.duration-ns' => 'duration→ns formatter helper; unit-assert harness pending',
  'pleme-lib.ephemeralId' => 'deterministic ephemeral-id helper; unit-assert harness pending',
  'pleme-lib.fleetHostname' => '4-part fleet hostname helper; unit-assert harness pending',
  'pleme-lib.composition.statusReflectStep' => 'crossplane composition status step; harness pending',
  'pleme-lib.crossplaneMRAP' => 'alias of pleme-lib.crossplaneManagedResourceActivationPolicy (COVERED) — define a fixture include or fold the alias',
  'pleme-lib.crossplaneXRD' => 'alias of pleme-lib.crossplaneCompositeResourceDefinition (COVERED) — define a fixture include or fold the alias',
  'pleme-lib.csiProvider' => 'CSI SecretProviderClass emitter; bare-fixture harness pending',
  'pleme-lib.delivery' => 'delivery/rollout emitter; bare-fixture harness pending',
  'pleme-lib.jetstream' => 'NATS JetStream Stream emitter; bare-fixture harness pending',
  'pleme-lib.jetstream-init-job' => 'JetStream bootstrap Job emitter; bare-fixture harness pending',
  'pleme-lib.resilience' => 'PDB+topology resilience bundle; bare-fixture harness pending',
  'pleme-lib.webhookInjection' => 'admission webhook CA-injection helper; bare-fixture harness pending'
}.freeze

# Minimum size sanity-check on the enumerated alphabet.
MIN_DEFINES = 300
# Coverage floor — covered (direct ∪ family) / total must stay above this.
COVERAGE_FLOOR = 0.90

# ── enumerate the alphabet ──────────────────────────────────────────────────
def all_defines
  Set.new(
    Dir.glob("#{LIB_TEMPLATES}/*.tpl").flat_map do |f|
      File.read(f).scan(/define\s+"(pleme-lib\.[^"]+)"/).flatten
    end
  )
end

# define -> {defines it includes} (the transitive-inclusion graph)
def inclusion_graph
  graph = Hash.new { |h, k| h[k] = Set.new }
  Dir.glob("#{LIB_TEMPLATES}/*.tpl").each do |f|
    current = nil
    File.read(f).each_line do |line|
      if (m = line.match(/define\s+"(pleme-lib\.[^"]+)"/))
        current = m[1]
      end
      next unless current

      line.scan(/(?:include|template)\s+"(pleme-lib\.[^"]+)"/).flatten.each do |inc|
        graph[current] << inc unless inc == current
      end
    end
  end
  graph
end

# defines `include`d under a directory tree
def includes_under(dir)
  Set.new(
    Dir.glob("#{dir}/**/*").select { |p| File.file?(p) }.flat_map do |p|
      File.read(p).scan(/(?:include|template)\s+"(pleme-lib\.[^"]+)"/).flatten
    rescue StandardError
      []
    end
  )
end

# A "tested unit" is a chart charts/<c> WITH a tests/<c>/*_test.yaml suite, OR a
# fixture corpus tests/_fixtures/<f>/templates (a harness exists only to be
# rendered by a suite). Collect every define those units include.
def directly_referenced
  refs = Set.new
  Dir.glob('charts/*').each do |cdir|
    chart = File.basename(cdir)
    next if Dir.glob("tests/#{chart}/*_test.yaml").empty?

    refs.merge(includes_under("#{cdir}/templates"))
  end
  Dir.glob('tests/_fixtures/*/templates').each do |tdir|
    refs.merge(includes_under(tdir))
  end
  refs
end

def family_defines(defines)
  Set.new(defines.select do |d|
    d.start_with?('pleme-lib.overlay.') || d.start_with?('pleme-lib.compliance.')
  end)
end

# ── the coverage computation ────────────────────────────────────────────────
def compute
  defines = all_defines
  family  = family_defines(defines)
  direct  = directly_referenced & defines
  graph   = inclusion_graph

  covered = Set.new(family) | direct
  # transitive closure: a define included by a covered define is exercised too
  loop do
    grew = false
    covered.dup.each do |c|
    graph[c].each do |inc|
        next unless defines.include?(inc) && !covered.include?(inc)

        covered << inc
        grew = true
      end
    end
    break unless grew
  end

  uncovered = defines.reject { |d| covered.include?(d) }
  { defines: defines, family: family, direct: direct, covered: covered, uncovered: uncovered }
end

# Proof that FAMILY credit is real: the compliance corpus must set every regime.
def verify_family_corpus
  corpus = Dir.glob('tests/pleme-microservice/compliance_*_test.yaml')
              .map { |f| File.read(f) }.join("\n")
  missing = REGIMES.reject { |r| corpus.include?(r) }
  missing
end

# ── run the checks ──────────────────────────────────────────────────────────
failures = []
result = compute
defines   = result[:defines]
family    = result[:family]
direct    = result[:direct]
covered   = result[:covered]
uncovered = result[:uncovered]

waived_keys = Set.new(WAIVED.keys)

# 1. non-trivial alphabet
if defines.size < MIN_DEFINES
  failures << "alphabet too small: found #{defines.size} defines, expected >= #{MIN_DEFINES}"
end

# 2. family credit is honest (corpus exercises every regime)
missing_regimes = verify_family_corpus
unless missing_regimes.empty?
  failures << "FAMILY CREDIT UNPROVEN — compliance corpus does not set these regimes " \
              "(overlay.* credit is fake without them): #{missing_regimes.join(', ')}"
end

# 3. every define covered OR waived
unwaived_holes = uncovered.reject { |d| waived_keys.include?(d) }
unless unwaived_holes.empty?
  failures << "ALPHABET INCOMPLETE — these defines have NO assertion and NO waiver " \
              "(add a tests/_fixtures/pleme-lib-bare harness + suite, or — only if " \
              "justified — a WAIVED entry):\n  #{unwaived_holes.sort.join("\n  ")}"
end

# 4. no stale waivers (a waived define that is now covered, or no longer exists)
stale = WAIVED.keys.select { |d| covered.include?(d) || !defines.include?(d) }
unless stale.empty?
  failures << "STALE WAIVERS — these are now covered (or removed); delete from WAIVED:\n" \
              "  #{stale.sort.join("\n  ")}"
end

# 5. coverage floor
covered_real = (covered & defines)
coverage = covered_real.size.to_f / defines.size
if coverage < COVERAGE_FLOOR
  failures << format('coverage %.1f%% below floor %.1f%%', coverage * 100, COVERAGE_FLOOR * 100)
end

# ── scoreboard ──────────────────────────────────────────────────────────────
waived_present = WAIVED.keys.count { |d| defines.include?(d) }
puts '── pleme-lib ALPHABET COMPLETENESS ─────────────────────────────────────'
puts format('  total defines : %4d', defines.size)
puts format('  covered       : %4d  (direct+transitive: %d, family overlay.*/compliance.*: %d)',
            covered_real.size, (direct | (covered_real - family)).size, family.size)
puts format('  waived (debt) : %4d', waived_present)
puts format('  coverage      : %5.1f%%  (floor %.1f%%)', coverage * 100, COVERAGE_FLOOR * 100)
puts '────────────────────────────────────────────────────────────────────────'

if failures.empty?
  puts 'ALPHABET COMPLETE ✓  every define is covered-or-waived; no stale waivers.'
  exit 0
else
  warn ''
  failures.each { |f| warn "✗ #{f}" }
  warn ''
  warn "ALPHABET CHECK FAILED (#{failures.size} problem#{failures.size == 1 ? '' : 's'})."
  exit 1
end
