#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# LPS-STATUSLINE Render Tests
# ═══════════════════════════════════════════════════════════════════════════════
# Feeds fixture JSON inputs through statusline.sh and asserts on the
# ANSI-stripped output. Run: bash tests/render-test.sh
# ═══════════════════════════════════════════════════════════════════════════════
# JSON fixtures are assembled by string concatenation on purpose:
# shellcheck disable=SC2089,SC2090

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../statusline.sh"

PASS=0
FAIL=0

# Render a JSON fixture through the statusline, ANSI codes stripped
render() {
    echo "$1" | bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g'
}

assert_contains() {
    local label="$1" output="$2" needle="$3"
    if [[ "$output" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "      expected to contain: $needle"
        echo "      got: $output"
    fi
}

assert_not_contains() {
    local label="$1" output="$2" needle="$3"
    if [[ "$output" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "      expected NOT to contain: $needle"
        echo "      got: $output"
    fi
}

# Future epochs for reset countdowns
NOW=$(date +%s)
IN_2H=$((NOW + 7200))
IN_1D=$((NOW + 86400))

RL='"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":'$IN_2H'},"seven_day":{"used_percentage":30,"resets_at":'$IN_1D'}}'

# ─── Model families and effort ────────────────────────────────────────────────

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"effort":{"level":"xhigh"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "fable5 + xhigh effort" "$out" "fable5(xhigh)"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable"},"effort":{"level":"high"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "versionless display name falls back to model id" "$out" "fable5(high)"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-mythos-5","display_name":"Mythos"},"effort":{"level":"max"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "mythos5 + max effort" "$out" "mythos5(max)"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-opus-4-8","display_name":"Opus"},"effort":{"level":"max"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "opus4.8 + max effort" "$out" "opus4.8(max)"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-opus-4-6","display_name":"Claude Opus 4.6"},"effort":{"level":"high"},"context_window":{"context_window_size":200000},'$RL'}')
assert_contains "legacy dotted display name still works" "$out" "opus4.6(high)"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-sonnet-5","display_name":"Sonnet"},"effort":{"level":"medium"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "sonnet5 + medium effort" "$out" "sonnet5(medium)"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-sonnet-4-5-20250929","display_name":"Sonnet 4.5"},"context_window":{"context_window_size":200000},'$RL'}')
assert_contains "dated model id parses version" "$out" "sonnet4.5"
assert_not_contains "no effort field -> no parentheses" "$out" "("

out=$(render '{"cwd":"/tmp","model":{"id":"claude-haiku-4-5-20251001","display_name":"Haiku"},"context_window":{"context_window_size":200000},'$RL'}')
assert_contains "haiku4.5" "$out" "haiku4.5"

# ─── Fast mode ────────────────────────────────────────────────────────────────

out=$(render '{"cwd":"/tmp","model":{"id":"claude-opus-4-8","display_name":"Opus"},"effort":{"level":"high"},"fast_mode":true,"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "fast mode shows electric ray" "$out" "⚡"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-opus-4-8","display_name":"Opus"},"effort":{"level":"high"},"fast_mode":false,"context_window":{"context_window_size":1000000},'$RL'}')
assert_not_contains "fast mode off hides electric ray" "$out" "⚡"

# ─── Native quota (rate_limits) ───────────────────────────────────────────────

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "5h percentage shown" "$out" "42%"
assert_contains "reset countdown shown" "$out" "⏱️"
assert_not_contains "7d hidden at 30%" "$out" "7d:"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":'$IN_2H'},"seven_day":{"used_percentage":80,"resets_at":'$IN_1D'}}}')
assert_contains "7d shown above 65%" "$out" "7d:80%"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000}}')
assert_not_contains "no rate_limits -> no quota section" "$out" "⏱️"

# ─── Extra-usage sirens (opt-in) ──────────────────────────────────────────────

OVER='{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":110,"resets_at":'$IN_2H'},"seven_day":{"used_percentage":50,"resets_at":'$IN_1D'}}}'

out=$(echo "$OVER" | LPS_STATUSLINE_EXTRA_USAGE=1 bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
assert_contains "sirens shown when opted in and >=100%" "$out" "🚨🚨🚨"

out=$(render "$OVER")
assert_not_contains "sirens hidden by default" "$out" "🚨"

out=$(echo '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},'$RL'}' | LPS_STATUSLINE_EXTRA_USAGE=1 bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
assert_not_contains "sirens hidden when opted in but under 100%" "$out" "🚨"

# ─── Context window ───────────────────────────────────────────────────────────

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000,"used_percentage":37},'$RL'}')
assert_contains "native used_percentage fallback (no transcript)" "$out" "🧠 37%"

out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},'$RL'}')
assert_contains "baseline estimate when nothing available" "$out" "🧠 ~"

# ─── Prompt cache ─────────────────────────────────────────────────────────────

IN_45M=$((NOW + 2700))
BASE='"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},'$RL
pc() { render '{'"$BASE"',"prompt_cache":{'"$1"'}}'; }

printf -v until_default '%(%Hh%M)T' "$IN_45M"
out=$(pc '"warm":true,"caching_observed":true,"ttl":"1h","expires_at":'$IN_45M',"misses":0,"last_miss_cause":null,"recache_tokens_if_cold":89823')
assert_contains "warm cache shows the clock time it goes cold" "$out" "cache until $until_default |"
assert_not_contains "no misses -> no miss marker" "$out" "✗"

printf -v until_colon '%(%H:%M)T' "$IN_45M"
out=$(echo '{'"$BASE"',"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":'$IN_45M',"misses":0}}' | LPS_STATUSLINE_TIME_FORMAT='%H:%M' bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
assert_contains "time format is configurable" "$out" "cache until $until_colon |"

out=$(pc '"warm":true,"caching_observed":true,"expires_at":null,"misses":0')
assert_contains "warm without expires_at" "$out" "cache warm |"

out=$(pc '"warm":false,"caching_observed":true,"expires_at":null,"misses":0,"recache_tokens_if_cold":89823')
assert_contains "cold cache shows tokens to re-cache" "$out" "cache cold 90k |"

out=$(pc '"warm":false,"caching_observed":true,"expires_at":null,"misses":0,"recache_tokens_if_cold":null')
assert_contains "cold right after compaction (recache null)" "$out" "cache cold |"

out=$(pc '"warm":false,"caching_observed":true,"misses":0,"recache_tokens_if_cold":1234567')
assert_contains "millions formatted with one decimal" "$out" "cache cold 1.2M |"
out=$(pc '"warm":false,"caching_observed":true,"misses":0,"recache_tokens_if_cold":999600')
assert_contains "rounding up to a million switches unit" "$out" "cache cold 1.0M |"
out=$(pc '"warm":false,"caching_observed":true,"misses":0,"recache_tokens_if_cold":950')
assert_contains "under 1000 tokens shown as-is" "$out" "cache cold 950 |"

out=$(pc '"warm":true,"caching_observed":true,"expires_at":'$IN_45M',"misses":2,"last_miss_cause":{"causes":["tools_changed"],"tools_added":3,"tools_removed":0}')
assert_contains "misses with last cause" "$out" "cache until $until_default ✗2 tools |"

out=$(pc '"warm":false,"caching_observed":true,"misses":1,"last_miss_cause":{"causes":["ttl_expired_1h"]},"recache_tokens_if_cold":120000')
assert_contains "idle expiry cause" "$out" "cache cold 120k ✗1 idle 1h |"

out=$(pc '"warm":true,"caching_observed":true,"expires_at":'$IN_45M',"misses":1,"last_miss_cause":{"causes":["thinking_display_changed","model_changed"]}')
assert_contains "unlisted cause falls back to its words; first cause only" "$out" "✗1 thinking display |"

out=$(pc '"warm":true,"caching_observed":true,"expires_at":'$IN_45M',"misses":3,"last_miss_cause":null')
assert_contains "misses without a diagnosed cause" "$out" "✗3 unknown |"

out=$(pc '"warm":false,"caching_observed":false,"expires_at":null,"misses":0,"recache_tokens_if_cold":5000')
assert_not_contains "caching not observed -> section hidden" "$out" "cache"

out=$(render '{'"$BASE"'}')
assert_not_contains "no prompt_cache field -> section hidden" "$out" "cache"

WARM='{'"$BASE"',"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":'$IN_45M',"misses":2,"last_miss_cause":{"causes":["tools_changed"]}}}'
for off in 0 false OFF no; do
    out=$(echo "$WARM" | LPS_STATUSLINE_CACHE=$off bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
    assert_not_contains "LPS_STATUSLINE_CACHE=$off hides the section" "$out" "cache"
done
out=$(echo "$WARM" | LPS_STATUSLINE_CACHE=1 bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
assert_contains "LPS_STATUSLINE_CACHE=1 keeps it" "$out" "cache until $until_default ✗2 tools |"
out=$(echo "$WARM" | LPS_STATUSLINE_CACHE='' bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
assert_contains "empty LPS_STATUSLINE_CACHE means default (on)" "$out" "cache until $until_default ✗2 tools |"

# ─── Regressions ──────────────────────────────────────────────────────────────

# R1: backslashes in the user's message must never be escape-expanded
# (printf %b would truncate at \c, expand \n into extra lines, emit raw \033)
tmp_transcript=$(mktemp)
printf '%s\n' '{"type":"user","message":{"content":"check C:\\config and \\now"}}' > "$tmp_transcript"
out=$(render '{"cwd":"/tmp","transcript_path":"'"$tmp_transcript"'","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000}}')
assert_contains "backslash content survives intact" "$out" 'C:\config and \now'
line_count=$(printf '%s\n' "$out" | wc -l)
if [ "$line_count" -eq 2 ]; then
    PASS=$((PASS + 1)); echo "  ok: output stays exactly two lines"
else
    FAIL=$((FAIL + 1)); echo "FAIL: output stays exactly two lines (got $line_count)"
fi
rm -f "$tmp_transcript"

# R3: unknown model family must not get its version appended twice
out=$(render '{"cwd":"/tmp","model":{"id":"claude-neo-2","display_name":"Neo 2"},"context_window":{"context_window_size":200000}}')
assert_contains "unknown family keeps display name as-is" "$out" "Neo 2"
assert_not_contains "unknown family version not doubled" "$out" "Neo 22"

# D2: 7d warning renders even when five_hour is absent
out=$(render '{"cwd":"/tmp","model":{"id":"claude-fable-5","display_name":"Fable 5"},"context_window":{"context_window_size":1000000},"rate_limits":{"seven_day":{"used_percentage":90,"resets_at":'$IN_1D'}}}')
assert_contains "7d shown without five_hour" "$out" "7d:90%"
assert_not_contains "no 5h section without five_hour" "$out" "⏱️"

# ─── Robustness ───────────────────────────────────────────────────────────────

out=$(echo 'not json at all' | bash "$STATUSLINE" | sed -e 's/\x1b\[[0-9;]*m//g')
assert_contains "invalid input handled" "$out" "invalid input"

out=$(render '{}')
assert_contains "empty object renders something" "$out" "unknown"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
