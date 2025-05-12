import os
import glob
import configparser
import json
import yaml
import xml.etree.ElementTree as ET

def summarize_issue(file, msg):
    print(f"[ISSUE] {file}: {msg}")

def analyze_ini(file):
    parser = configparser.ConfigParser()
    try:
        parser.read(file)
        print(f"[OK] {file}: INI/CONF syntax valid.")
    except Exception as e:
        summarize_issue(file, f"INI/CONF parse error: {e}")

def analyze_json(file):
    try:
        with open(file) as f:
            json.load(f)
        print(f"[OK] {file}: JSON syntax valid.")
    except Exception as e:
        summarize_issue(file, f"JSON parse error: {e}")

def analyze_yaml(file):
    try:
        with open(file) as f:
            yaml.safe_load(f)
        print(f"[OK] {file}: YAML syntax valid.")
    except Exception as e:
        summarize_issue(file, f"YAML parse error: {e}")

def analyze_xml(file):
    try:
        ET.parse(file)
        print(f"[OK] {file}: XML syntax valid.")
    except Exception as e:
        summarize_issue(file, f"XML parse error: {e}")

def analyze_env(file):
    try:
        with open(file) as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    if "=" not in line:
                        summarize_issue(file, f".env line missing '=': {line.strip()}")
        print(f"[OK] {file}: .env syntax checked.")
    except Exception as e:
        summarize_issue(file, f".env parse error: {e}")

def analyze_service(file):
    try:
        with open(file) as f:
            for line in f:
                if line.startswith("WorkingDirectory=") and not line.split("=",1)[1].strip().startswith("/"):
                    summarize_issue(file, "WorkingDirectory is not absolute!")
        print(f"[OK] {file}: .service file syntax checked.")
    except Exception as e:
        summarize_issue(file, f".service parse error: {e}")

def main():
    config_patterns = [
        "/etc/**/*.conf", "/etc/**/*.ini", "/etc/**/*.service",
        "/etc/**/*.env", "/etc/**/*.yaml", "/etc/**/*.yml",
        "/etc/**/*.json", "/etc/**/*.xml",
        "/home/**/*.conf", "/home/**/*.ini", "/home/**/*.service",
        "/home/**/*.env", "/home/**/*.yaml", "/home/**/*.yml",
        "/home/**/*.json", "/home/**/*.xml",
    ]
    files = set()
    for pat in config_patterns:
        files.update(glob.glob(pat, recursive=True))
    for file in files:
        ext = file.split(".")[-1]
        if ext in ("conf", "ini"):
            analyze_ini(file)
        elif ext == "json":
            analyze_json(file)
        elif ext in ("yaml", "yml"):
            analyze_yaml(file)
        elif ext == "xml":
            analyze_xml(file)
        elif ext == "env":
            analyze_env(file)
        elif ext == "service":
            analyze_service(file)
        else:
            print(f"[SKIP] {file}: Unknown config type.")

if __name__ == "__main__":
    main()
