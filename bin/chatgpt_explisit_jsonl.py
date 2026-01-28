import json
import os
import sys
import argparse
import glob
from pathlib import Path

def get_session_name(data, index):
    # ChatGPT exports use "title", others might use "name"
    name = data.get("title") or data.get("name") or f"Session_{index}"
    # Clean filename: remove non-alphanumeric except spaces/underscores
    clean_name = "".join([c for c in name if c.isalnum() or c in (' ', '-', '_')]).strip()
    return clean_name if clean_name else f"Session_{index}"

def extract_sessions(input_file, output_dir):
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            
            # Detect format: Standard JSON (starts with [) or JSONL
            if content.startswith('['):
                all_data = json.loads(content)
            else:
                # Fallback for JSONL format
                all_data = [json.loads(line) for line in content.splitlines() if line.strip()]

        count = 0
        for i, session in enumerate(all_data):
            if not session: continue
            
            name = get_session_name(session, i)
            session_file = out_path / f"{name}.jsonl"
            
            with open(session_file, 'w', encoding='utf-8') as sf:
                # Store as a single line JSONL for compatibility with Script 2
                sf.write(json.dumps(session) + '\n')
            count += 1
            
        print(f"Successfully extracted {count} sessions to: {out_path}")
        
    except Exception as e:
        print(f"Error during extraction: {e}")
        if "list" in str(e).lower():
            print("Tip: The file structure was a List, not a Dictionary per line.")

def combine_sessions(output_file, input_sources):
    try:
        with open(output_file, 'w', encoding='utf-8') as out:
            for src in input_sources:
                files = glob.glob(src) if '*' in src else [src]
                for f_path in sorted(files):
                    p = Path(f_path)
                    if p.is_file():
                        with open(p, 'r', encoding='utf-8') as infile:
                            for line in infile:
                                if line.strip(): out.write(line.strip() + '\n')
                        print(f"Added: {p.name}")
        print(f"Created bundle: {output_file}")
    except Exception as e:
        print(f"Error during combination: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="JSONL Session Manager")
    parser.add_argument("-x", "--extract", nargs=2, metavar=('FILE', 'DIR'))
    parser.add_argument("-c", "--combine", nargs='+', metavar=('OUT', 'IN'))
    
    args = parser.parse_args()
    if args.extract:
        extract_sessions(args.extract[0], args.extract[1])
    elif args.combine:
        combine_sessions(args.combine[0], args.combine[1:])
    else:
        parser.print_help()

