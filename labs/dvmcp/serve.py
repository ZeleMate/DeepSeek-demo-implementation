# Our stdio entry point for one DVMCP challenge (#59). Usage: serve.py <challenge>, e.g. challenge4.
# Upstream's servers end in mcp.run(transport="streamable-http") under `if __name__ == "__main__"`,
# so importing one builds its FastMCP server without starting it. This serves it on stdio instead:
# dsh starts one container per attempt, so no state (challenge 4's call counter) outlives it.
import importlib.util
import sys
from pathlib import Path

CHALLENGES = {
    "challenge2": "easy/challenge2",
    "challenge3": "easy/challenge3",
    "challenge4": "medium/challenge4",
    "challenge7": "medium/challenge7",
}


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in CHALLENGES:
        sys.exit(f"usage: serve.py {{{'|'.join(CHALLENGES)}}}")
    name = sys.argv[1]
    path = Path(__file__).parent / "challenges" / CHALLENGES[name] / "server.py"
    spec = importlib.util.spec_from_file_location(f"dvmcp_{name}", path)
    if spec is None or spec.loader is None:
        sys.exit(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # stdout carries the protocol, so the delivery line goes to stderr, which dsh passes through.
    # eval/lib/dvmcp.ts reads it to tell that the expected challenge ran.
    print(f"[dvmcp] {name} started", file=sys.stderr, flush=True)
    module.mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
