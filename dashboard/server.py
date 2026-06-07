#!/usr/bin/env python3
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = Path(__file__).resolve().parent


def load(path: Path, fallback):
    if not path.exists():
        return fallback
    return json.loads(path.read_text(encoding="utf-8"))


def snapshot():
    return {
        "compiler": {
            "graph_ir": load(ROOT / "compiler_artifacts/cv_graph_ir.json", {}),
            "fusion": load(ROOT / "compiler_artifacts/cv_fusion_report.json", {}),
            "memory": load(ROOT / "compiler_artifacts/cv_memory_plan.json", {}),
            "execution_plan": load(ROOT / "compiler_artifacts/cv_execution_plan.json", {}),
            "cost": load(ROOT / "compiler_artifacts/cv_cost_report.json", {}),
        },
        "core_value": load(ROOT / "benchmark_reports/core_value_evidence.json", {}),
        "runtime": load(ROOT / "runtime_artifacts/runtime_benchmark_report.json", {}),
        "compression": load(ROOT / "compression_artifacts/model_compression_report.json", {}),
        "llm": load(ROOT / "llm_artifacts/pocketchef_llm_benchmark_report.json", {}),
        "llm_serving": load(ROOT / "llm_artifacts/serving/llm_serving_evidence.json", {}),
        "combined": load(ROOT / "benchmark_reports/combined_benchmark_report.json", {}),
    }


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/snapshot":
            payload = json.dumps(snapshot(), indent=2).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        if self.path == "/":
            self.path = "/static/index.html"

        return super().do_GET()

    def translate_path(self, path):
        rel = path.lstrip("/")
        return str(DASHBOARD / rel)


def main():
    host = "127.0.0.1"
    port = 8766
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"PocketChef-AI dashboard: http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
