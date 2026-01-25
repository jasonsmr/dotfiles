import os
import sys
import subprocess
from pathlib import Path

def get_file_info(path):
    """Gets human-readable size and 'file' command description."""
    try:
        # Get Size
        size = os.path.getsize(path)
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024.0:
                break
            size /= 1024.0
        size_str = f"{size:.1f}{unit}"

        # Get File Description (equivalent to 'file -b')
        # -b (brief) prevents the filename from being repeated in the output
        result = subprocess.run(['file', '-b', str(path)], 
                                capture_output=True, text=True)
        file_desc = result.stdout.strip()
        
        return f"[{size_str:>7}]  {file_desc}"
    except Exception:
        return "[ unknown ]  Error reading file"

def print_tree(directory, prefix=""):
    """Recursively prints the tree with file information."""
    path_obj = Path(directory)
    if not path_obj.exists():
        print(f"Error: {directory} does not exist.")
        return

    # Get list of all files/dirs (including hidden ones starting with .)
    try:
        items = sorted(list(path_obj.iterdir()), key=lambda x: x.name)
    except PermissionError:
        print(f"{prefix}└── [Permission Denied]")
        return

    for i, item in enumerate(items):
        is_last = (i == len(items) - 1)
        connector = "└── " if is_last else "├── "
        
        # Gather info for the current item
        info = get_file_info(item)
        print(f"{prefix}{connector}{item.name:<25} {info}")

        # If it's a directory, recurse
        if item.is_dir() and not item.is_symlink():
            extension = "    " if is_last else "│   "
            print_tree(item, prefix + extension)

if __name__ == "__main__":
    # Default to current directory if no argument is passed
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    
    print(f"Listing for: {os.path.abspath(target_dir)}")
    print("-" * 80)
    print_tree(target_dir)

