#!/usr/bin/env bash
# worker_codex_runtime() resolution + vetting (round-1 review of the portability fix): the npm
# and native-ELF layouts must resolve; an npm shim script, a non-executable file, and a
# group/world-writable binary must be REJECTED. Pure logic — no sudo, runs in CI. Rejection is
# asserted as "our planted candidate was not chosen" (the box's own real install, if any, may
# still resolve — that is correct behaviour, not a test failure).
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x .venv/bin/python ] || { echo "SKIP codex_runtime.sh: .venv absent"; exit 77; }

if .venv/bin/python - <<'PY'
import importlib.util, os, pathlib, shutil, sys, tempfile
s = importlib.util.spec_from_file_location("d", "scripts/dispatch.py")
d = importlib.util.module_from_spec(s); s.loader.exec_module(d)

ELF = b"\x7fELF" + b"\x00" * 60
fails = []

def probe(setup):
    """Run worker_codex_runtime with OPERATOR_HOME pointed at a fresh fake home; return
    (result, home). setup(home) plants this case's candidate files."""
    home = pathlib.Path(tempfile.mkdtemp())
    setup(home)
    d.OPERATOR_HOME = home
    d.CODEX_PKG = home / ".local/lib/node_modules/@openai/codex"
    return d.worker_codex_runtime(), home

def chose_ours(got, home):
    return got is not None and str(got[2]).startswith(str(home))

def case(name, setup, expect_ours):
    got, home = probe(setup)
    if chose_ours(got, home) != expect_ours:
        fails.append(f"{name}: expected ours={expect_ours}, got {got}")
    else:
        print(f"  ok: {name}")
    shutil.rmtree(home, ignore_errors=True)

def native(home, mode=0o755, body=ELF, name=".codex/bin/codex"):
    p = home / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(body); p.chmod(mode)
    return p

# 1. native ELF, executable, owner-only-writable -> accepted
case("native ELF accepted", lambda h: native(h), True)
# 2. npm shim (node script) planted as the native candidate -> rejected (needs node, not standalone)
case("npm shim rejected", lambda h: native(h, body=b"#!/usr/bin/env node\nrequire('x')\n"), False)
# 3. non-executable ELF -> rejected
case("non-executable ELF rejected", lambda h: native(h, mode=0o644), False)
# 4. world-writable ELF -> rejected (worker-swappable mount source); group-writable stays
#    accepted (Ubuntu user-private-group umask; the worker is never in the operator's group)
case("world-writable ELF rejected", lambda h: native(h, mode=0o777), False)
case("group-writable ELF accepted", lambda h: native(h, mode=0o775), True)
# 5. symlinked candidate -> accepted via its resolved real path
def symlinked(h):
    real = native(h, name=".codex/versions/1.0/codex")
    (h / ".codex/bin").mkdir(parents=True, exist_ok=True)
    os.symlink(real, h / ".codex/bin/codex")
case("symlink resolved and accepted", symlinked, True)
got, home = probe(symlinked)
if got and "versions/1.0" not in str(got[2]):
    fails.append(f"symlink entry not resolved to real path: {got[2]}")
shutil.rmtree(home, ignore_errors=True)
# 6. npm layout (codex.js + system node) -> accepted, argv runs node (only testable where
#    /usr/bin/node exists; the vetting logic is identical either way)
if pathlib.Path("/usr/bin/node").exists():
    def npm(h):
        pkg = h / ".local/lib/node_modules/@openai/codex/bin"
        pkg.mkdir(parents=True)
        (pkg / "codex.js").write_text("// entry\n")
    got, home = probe(npm)
    if not (chose_ours(got, home) and got[0][0] == "/usr/bin/node"):
        fails.append(f"npm layout not resolved via node: {got}")
    else:
        print("  ok: npm layout accepted via system node")
    shutil.rmtree(home, ignore_errors=True)
else:
    print("  skip: npm-layout case (/usr/bin/node absent; native cases above still ran)")

for f in fails:
    print(f"  FAIL {f}")
sys.exit(1 if fails else 0)
PY
then echo "PASS codex_runtime.sh"; else echo "FAIL codex_runtime.sh"; exit 1; fi
