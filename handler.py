import json
import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


def handler(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handler function for ComfyUI workflow execution.
    
    Expects input in the following format:
    {
        "input": {
            "workflow": {
                // ComfyUI workflow nodes
            }
        }
    }
    """
    try:
        # Extract the workflow from the event input
        input_data = event.get("input", {})
        workflow = input_data.get("workflow")
        
        if not workflow:
            return {
                "status": "error",
                "message": "No workflow provided in input"
            }
        
        logger.info(f"Processing workflow with {len(workflow)} nodes")
        
        # TODO: Integrate with ComfyUI API to execute the workflow
        # This would typically involve:
        # 1. Connecting to the ComfyUI server (localhost:8188)
        # 2. Posting the workflow to the /prompt endpoint
        # 3. Monitoring the execution status
        # 4. Returning the results
        
        result = {
            "status": "success",
            "message": "Workflow queued for processing",
            "workflow_nodes": len(workflow),
            # TODO: Add actual execution results here
        }
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing workflow: {str(e)}")
        return {
            "status": "error",
            "message": f"Failed to process workflow: {str(e)}"
        }


# Required: Start the RunPod serverless handler
try:
    import runpod
    runpod.serverless.start({"handler": handler})
except ImportError:
    # If runpod is not installed, allow testing with test_input.json or --test_input flag
    if __name__ == "__main__":
        import sys
        
        # Support for --test_input flag
        test_input = None
        if "--test_input" in sys.argv:
            idx = sys.argv.index("--test_input")
            if idx + 1 < len(sys.argv):
                test_input = json.loads(sys.argv[idx + 1])
        
        # If no --test_input flag, try to load from test_input.json
        if test_input is None:
            try:
                with open("test_input.json", "r") as f:
                    test_input = json.load(f)
            except FileNotFoundError:
                test_input = {"input": {}}
        
        result = handler(test_input)
        print(json.dumps(result, indent=2))
