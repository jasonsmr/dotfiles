import json
import sys
import argparse
from pathlib import Path

def extract_text(data):
    """Recursively searches for 'role' and 'content' or 'parts' in nested data."""
    extracted = []
    
    if isinstance(data, dict):
        # Case 1: Standard role/content pair
        if "role" in data and ("content" in data or "parts" in data):
            role = data.get("role", "User").capitalize()
            content = data.get("content", "")
            # Handle list-based content (common in some exports)
            if isinstance(content, list):
                content = "\n".join(str(p) for p in content)
            elif isinstance(content, dict):
                content = content.get("parts", [""])[0] if "parts" in content else str(content)
            extracted.append((role, content))
        
        # Case 2: Deep dive into other keys (like 'messages', 'mapping', etc.)
        for key, value in data.items():
            extracted.extend(extract_text(value))
            
    elif isinstance(data, list):
        for item in data:
            extracted.extend(extract_text(item))
            
    return extracted

def convert_jsonl_to_markdown(input_path, output_path):
    in_file = Path(input_path).resolve()
    out_file = Path(output_path).resolve()

    if not in_file.exists():
        print(f"Error: Input file not found at {in_file}")
        sys.exit(1)

    try:
        with open(in_file, 'r', encoding='utf-8') as f, \
             open(out_file, 'w', encoding='utf-8') as out:
            
            for line in f:
                if not line.strip(): continue
                try:
                    line_data = json.loads(line)
                    messages = extract_text(line_data)
                    
                    for role, content in messages:
                        if content.strip():
                            out.write(f"## {role}\n\n")
                            out.write(f"{content}\n\n")
                            out.write("---\n\n")
                except json.JSONDecodeError:
                    continue 

        print(f"Successfully created: {out_file}")
        print(f"Extracted Size: {out_file.stat().st_size} bytes")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()
    convert_jsonl_to_markdown(args.input, args.output)

