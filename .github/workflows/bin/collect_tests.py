import json
import os


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.abspath(os.path.join(script_dir, '..', '..', '..'))
    tests = []
    for dirpath, dirnames, filenames in os.walk(repo_dir):
        for f in filenames:
            if f.startswith("test_"):
                tests.append(os.path.join(dirpath, f))

    tests_rel = [os.path.relpath(p, repo_dir) for p in tests]

    print(json.dumps({"testbench": tests_rel}))
