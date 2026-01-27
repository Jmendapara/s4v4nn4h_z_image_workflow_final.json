import json
import sys
import os

# Add the project directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import handler directly without runpod dependency for testing
from handler import handler

# Load example request
with open("test_input.json", "r") as f:
    example_request = json.load(f)

# Test the handler
print("Testing handler with example-request.json...")
print("-" * 60)

result = handler(example_request)

print("\nHandler Result:")
print(json.dumps(result, indent=2))
print("-" * 60)

# Verify the result
if result.get("status") == "success":
    print("\n✓ Handler executed successfully")
    print(f"✓ Workflow nodes detected: {result.get('workflow_nodes')}")
else:
    print("\n✗ Handler returned an error")
    print(f"Error: {result.get('message')}")
