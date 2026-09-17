#!/usr/bin/env python3
import json
import os
from flask import Flask, jsonify, request

app = Flask(__name__)

NAMES_FILE = "/opt/wg-portal/names.json"
DEFAULTS = {
    "net1": "Сеть 1",
    "net2": "Сеть 2",
    "net3": "Сеть 3",
    "net4": "Сеть 4",
}


def load_names():
    if not os.path.exists(NAMES_FILE):
        return dict(DEFAULTS)
    try:
        with open(NAMES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        # дополняем отсутствующие ключи дефолтами
        for k, v in DEFAULTS.items():
            data.setdefault(k, v)
        return data
    except Exception:
        return dict(DEFAULTS)


def save_names(data):
    with open(NAMES_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


@app.route("/api/names", methods=["GET"])
def get_names():
    return jsonify(load_names())


@app.route("/api/names", methods=["POST"])
def set_names():
    payload = request.get_json(silent=True) or {}
    key = payload.get("key")
    name = (payload.get("name") or "").strip()

    if not key or not name:
        return jsonify({"error": "key and name are required"}), 400

    if key not in DEFAULTS:
        return jsonify({"error": "unknown network key"}), 400

    if len(name) > 100:
        return jsonify({"error": "name too long"}), 400

    data = load_names()
    data[key] = name
    save_names(data)
    return jsonify({"ok": True, "key": key, "name": name})


@app.route("/api/names/reset", methods=["POST"])
def reset_names():
    save_names(dict(DEFAULTS))
    return jsonify({"ok": True})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
