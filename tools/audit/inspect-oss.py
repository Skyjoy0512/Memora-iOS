"""Collect public source evidence through the already authenticated gh CLI.

Writes evidence outside the checkout, never clones or executes upstream code.
Unavailable repositories, releases and paths remain explicit errors.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def github(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=40)
    if result.returncode:
        raise RuntimeError(result.stderr.strip().splitlines()[0][:300])
    return json.loads(result.stdout)


def inspect(candidate, output):
    repo = candidate["repo"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid repository")
    evidence = {"repo": repo, "category": candidate["category"], "url": "https://github.com/" + repo}
    try:
        metadata = github("repos/" + repo)
        evidence.update({key: metadata.get(key) for key in ["archived", "disabled", "pushed_at", "default_branch", "license"]})
        commit = github("repos/" + repo + "/commits/" + metadata["default_branch"])
        sha = commit["sha"]
        evidence["head"] = {"sha": sha, "date": commit["commit"]["committer"]["date"], "url": commit["html_url"]}
        try:
            release = github("repos/" + repo + "/releases/latest")
            evidence["latestRelease"] = {key: release.get(key) for key in ["tag_name", "published_at", "html_url", "prerelease"]}
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            evidence["releaseError"] = str(error)
        sources = []
        for path in candidate["paths"]:
            url = "https://raw.githubusercontent.com/" + repo + "/" + sha + "/" + path
            source = {"path": path, "url": url}
            try:
                with urllib.request.urlopen(url, timeout=30) as response:
                    raw = response.read(1_048_577)
                if len(raw) > 1_048_576:
                    raise ValueError("Source exceeds evidence size limit")
                folder = output / repo.replace("/", "--")
                folder.mkdir(exist_ok=True)
                destination = folder / path.replace("/", "--")
                destination.write_bytes(raw)
                decoded = raw.decode("utf-8", errors="replace")
                patterns = r"swift-tools-version|\.iOS|swiftLanguage|dependencies|dependency|license|SPDX|platforms|node|Notes|notes|chart|table|theme|master|loadPresentation|savePresentation|authentication|Swift 6|maintenance"
                matches = [(number, line[:240]) for number, line in enumerate(decoded.splitlines(), 1)
                           if re.search(patterns, line, re.I)]
                source.update(sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw), localPath=str(destination), signals=matches[:16])
            except (OSError, ValueError, urllib.error.URLError) as error:
                source["error"] = str(error)[:300]
            sources.append(source)
        evidence["sources"] = sources
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        evidence["error"] = str(error)[:300]
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.expanduser().resolve()
    if output == ROOT or ROOT in output.parents:
        parser.error("Evidence must be outside the checkout")
    output.mkdir(parents=True, exist_ok=False)
    candidates = json.loads((ROOT / "tools/audit/oss-candidates.json").read_text())
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(lambda candidate: inspect(candidate, output), candidates))
    (output / "evidence.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    for result in results:
        print(json.dumps({"repo": result["repo"], "head": result.get("head"), "release": result.get("latestRelease"),
                          "license": (result.get("license") or {}).get("spdx_id"), "archived": result.get("archived"),
                          "error": result.get("error"), "sourcesRead": sum("sha256" in s for s in result.get("sources", []))}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
