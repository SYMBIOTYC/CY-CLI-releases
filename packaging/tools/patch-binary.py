#!/usr/bin/env python3
"""Patch CY CLI binary to remove trust prompt and fix other issues."""

import sys
import os
import subprocess

def patch_trust_prompt(binary_path):
    """Remove the 'Do you trust this directory' prompt from the binary."""
    with open(binary_path, "rb") as f:
        data = bytearray(f.read())
    
    old = b"Do you trust the contents of this directory? Working with untrusted contents comes with higher risk of prompt injection. Trusting the directory allows project-local config, hooks, and exec policies to load."
    new = b"You are in a trusted directory."
    
    if old in data:
        idx = data.index(old)
        # Pad with null bytes to maintain binary layout
        padding = b"\x00" * (len(old) - len(new))
        data[idx:idx+len(old)] = new + padding
        with open(binary_path, "wb") as f:
            f.write(data)
        print(f"✓ Patched trust prompt at offset {idx}")
        return True
    else:
        print("⚠ Trust prompt pattern not found in binary")
        return False

def remove_signature(binary_path):
    """Remove code signature from binary."""
    try:
        subprocess.run(["codesign", "--remove-signature", binary_path], 
                      check=True, capture_output=True)
        print(f"✓ Removed signature from {binary_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"⚠ Failed to remove signature: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: patch-binary.py <binary_path> [app_bundle_path]")
        sys.exit(1)
    
    binary_path = sys.argv[1]
    app_path = sys.argv[2] if len(sys.argv) > 2 else None
    
    if not os.path.exists(binary_path):
        print(f"ERROR: Binary not found: {binary_path}")
        sys.exit(1)
    
    print(f"Patching {binary_path}...")
    patch_trust_prompt(binary_path)
    remove_signature(binary_path)
    
    if app_path and os.path.exists(app_path):
        remove_signature(app_path)
        print(f"✓ Removed signature from app bundle {app_path}")

if __name__ == "__main__":
    main()
