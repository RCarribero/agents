#!/usr/bin/env python3
"""
verified_digest.py — Compute and verify file-set digests for Fase 3 consensus.

Commands:
  compute          Hash a set of files and print the digest.
  verify-consensus Check that a given digest matches a set of files.

Usage:
  python scripts/verified_digest.py compute [--workspace-root ROOT] FILE [FILE ...]
  python scripts/verified_digest.py verify-consensus --digest DIGEST [--workspace-root ROOT] FILE [FILE ...]

Examples:
  python ./scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md
  python ./scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md agents/devops.agent.md
  python ./scripts/verified_digest.py verify-consensus --digest <hash> --workspace-root . agents/orchestrator.agent.md
"""

import argparse
import hashlib
import os
import sys


def compute_digest(workspace_root: str, files: list[str]) -> str:
    """
    Compute a SHA-256 digest over a sorted list of (relative_path, content) pairs.
    Files are resolved relative to workspace_root if they are not absolute paths.
    Paths are normalised to forward-slash form before hashing so the digest is
    platform-independent.
    """
    hasher = hashlib.sha256()
    for rel in sorted(files):
        if os.path.isabs(rel):
            resolved = rel
            key = rel.replace("\\", "/")
        else:
            resolved = os.path.join(workspace_root, rel)
            key = rel.replace("\\", "/")

        if not os.path.isfile(resolved):
            print(f"ERROR: file not found: {resolved}", file=sys.stderr)
            sys.exit(1)

        with open(resolved, "rb") as fh:
            content = fh.read()

        hasher.update(key.encode())
        hasher.update(b"\n")
        hasher.update(content)
        hasher.update(b"\n")

    return hasher.hexdigest()


def cmd_compute(args: argparse.Namespace) -> None:
    digest = compute_digest(args.workspace_root, args.files)
    print(digest)


def cmd_verify_consensus(args: argparse.Namespace) -> None:
    computed = compute_digest(args.workspace_root, args.files)
    if computed == args.digest:
        print(f"OK: digest matches ({computed})")
        sys.exit(0)
    else:
        print(f"MISMATCH: expected {args.digest}, got {computed}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compute or verify a verified_digest over a set of files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # compute
    p_compute = subparsers.add_parser("compute", help="Hash files and print digest.")
    p_compute.add_argument(
        "--workspace-root",
        default=".",
        metavar="ROOT",
        help="Root directory to resolve relative file paths (default: current dir).",
    )
    p_compute.add_argument("files", nargs="+", metavar="FILE", help="Files to include in the digest.")
    p_compute.set_defaults(func=cmd_compute)

    # verify-consensus
    p_verify = subparsers.add_parser("verify-consensus", help="Verify digest matches files.")
    p_verify.add_argument("--digest", required=True, metavar="DIGEST", help="Expected hex digest.")
    p_verify.add_argument(
        "--workspace-root",
        default=".",
        metavar="ROOT",
        help="Root directory to resolve relative file paths (default: current dir).",
    )
    p_verify.add_argument("files", nargs="+", metavar="FILE", help="Files to hash and compare.")
    p_verify.set_defaults(func=cmd_verify_consensus)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
