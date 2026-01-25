import json
import sys
import argparse
import re
from pathlib import Path

def get_chatgpt_messages(data):
    """Specific extractor for ChatGPT's mapping-style JSON."""
    extracted = []
    mapping = data.get("mapping", {})
    
    # ChatGPT conversations are often stored in a mapping (dictionary of nodes)
    # We need to sort them or traverse them. For simplicity, we find nodes with messages.
    for node_id in mapping:
        node = mapping[node_id]
        message = node.get("message")
        
        if message:
            role = message.get("author", {}).get("role", "Unknown").capitalize()
            content_obj = message.get("content", {})
            
            # ChatGPT stores text in a list called 'parts'
            parts = content_obj.get("parts", [])
            text_content = ""
            
            for part in parts:
                if isinstance(part, str):
                    text_content += part
                elif isinstance(part, dict):
                    # Handle cases where part is a rich-text object
                    text_content += part.get("text", "")

            # Only add if there is actual text to show
            if text_content.strip():
                extracted.append((role, text_content.strip()))
    
    return extracted

def jsonl_to_md(jsonl_path, md_path):
    try:
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            line = f.readline()
            if not line: return
            data = json.loads(line)
        
        with open(md_path, 'w', encoding='utf-8') as out:
            # 1. Keep metadata for MJ conversion (Script Compatibility)
            out.write(f"<!-- METADATA_START\n{json.dumps(data)}\nMETADATA_END -->\n\n")
            
            title = data.get("title") or Path(jsonl_path).stem
            out.write(f"# {title}\n\n")
            
            # 2. Extract content using the ChatGPT-specific mapper
            messages = get_chatgpt_messages(data)
            
            if not messages:
                out.write("> *No readable message content found in this session.*\n")
            
            for role, content in messages:
                out.write(f"## {role}\n\n{content}\n\n---\n\n")
                
        print(f"Successfully converted to MD: {md_path}")
    except Exception as e:
        print(f"Conversion Error (JM): {e}")

def md_to_jsonl(md_path, jsonl_path):
    try:
        with open(md_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Search for the hidden metadata block
        meta_match = re.search(r"<!-- METADATA_START\n(.*?)\nMETADATA_END -->", content, re.DOTALL)
        
        if meta_match:
            original_json = meta_match.group(1).strip()
            with open(jsonl_path, 'w', encoding='utf-8') as out:
                out.write(original_json + '\n')
            print(f"Restored JSONL: {jsonl_path}")
        else:
            print("Error: No metadata block found. File was likely edited or is invalid.")
    except Exception as e:
        print(f"Conversion Error (MJ): {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ChatGPT Bi-directional Converter")
    parser.add_argument("-jm", nargs=2, metavar=('IN_JSONL', 'OUT_MD'))
    parser.add_argument("-mj", nargs=2, metavar=('IN_MD', 'OUT_JSONL'))
    
    args = parser.parse_args()
    if args.jm:
        jsonl_to_md(args.jm[0], args.jm[1])
    elif args.mj:
        md_to_jsonl(args.mj[0], args.mj[1])
    else:
        parser.print_help()

