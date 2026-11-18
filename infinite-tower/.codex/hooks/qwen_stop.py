import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path


def emit(data):
    print(json.dumps(data))
    sys.exit(0)


def get_project_root(cwd):
    result = subprocess.run(
        ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True
    )
    return Path(result.stdout.strip()).resolve()


def main():
    try:
        event = json.load(sys.stdin)

        # Prevent a repeated Stop-hook continuation.
        if event.get("stop_hook_active", False):
            emit({})

        cwd = Path(event.get("cwd") or os.getcwd()).resolve()
        root = get_project_root(cwd)
        os.chdir(root)

        reviewer_path = root / "tools" / "ai_reviewer" / "review.py"

        if not reviewer_path.is_file():
            emit({
                "systemMessage": "Qwen reviewer script was not found."
            })

        # Import the existing reviewer to detect relevant changes.
        spec = importlib.util.spec_from_file_location(
            "qwen_reviewer",
            reviewer_path
        )

        reviewer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reviewer)

        diff, _ = reviewer.get_changes()

        if not diff.strip():
            emit({})

        # Fingerprint the current changes.
        fingerprint = hashlib.sha256(
            diff.encode("utf-8")
        ).hexdigest()

        # Store review state outside the project.
        cache_dir = (
            Path.home()
            / "Library"
            / "Caches"
            / "InfiniteTowerQwenReview"
        )

        cache_dir.mkdir(parents=True, exist_ok=True)

        project_id = hashlib.sha256(
            str(root).encode("utf-8")
        ).hexdigest()

        state_file = cache_dir / f"{project_id}.json"

        if state_file.exists():
            try:
                state = json.loads(
                    state_file.read_text(encoding="utf-8")
                )

                if state.get("fingerprint") == fingerprint:
                    emit({})

            except (OSError, json.JSONDecodeError):
                pass

        report_path = (
            root
            / "tools"
            / "ai_reviewer"
            / "review_report.md"
        )

        previous_mtime = (
            report_path.stat().st_mtime_ns
            if report_path.exists()
            else 0
        )

        # Run Qwen through the existing reviewer.
        result = subprocess.run(
            [sys.executable, str(reviewer_path)],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=300
        )

        if result.returncode != 0 or "Review completed!" not in result.stdout:
            diagnostic = result.stderr[-800:] or result.stdout[-800:]
            emit({
                "systemMessage": (
                    "The reviewer did not complete successfully. "
                    + diagnostic
                )
            })

        if (
            not report_path.is_file()
            or report_path.stat().st_mtime_ns <= previous_mtime
        ):
            emit({
                "systemMessage": (
                    "The Qwen review report was not freshly updated."
                )
            })

        # Remember the successfully reviewed changes.
        state_file.write_text(
            json.dumps({
                "fingerprint": fingerprint
            }),
            encoding="utf-8"
        )

        # Ask Codex to continue and present the review.
        emit({
            "decision": "block",
            "reason": (
                "The local Qwen code review has completed. "
                "Read the latest report at "
                "tools/ai_reviewer/review_report.md. "
                "Present its findings to the user, distinguish "
                "confirmed issues from possible concerns, and "
                "do not modify any files. Do not commit anything."
            )
        })

    except subprocess.TimeoutExpired:
        emit({
            "systemMessage": (
                "Qwen review timed out. Check Ollama and try again."
            )
        })

    except Exception as error:
        emit({
            "systemMessage": (
                "Qwen hook encountered an error: "
                + str(error)[:800]
            )
        })


if __name__ == "__main__":
    main()
