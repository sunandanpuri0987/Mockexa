import os
import sys
import logging
from pathlib import Path

# Add backend directory to sys.path so 'app' can be imported
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.providers.gd_backend import LocalQwenBackend
from app.providers.llm_backend import GenerationRequest

logging.basicConfig(level=logging.INFO)

def run():
    model_dir = Path("group_d/model")
    try:
        backend = LocalQwenBackend.get_instance(model_dir=model_dir)
    except Exception as e:
        print(f"FAILED TO LOAD: {e}")
        sys.exit(1)
        
    req = GenerationRequest(
        task="gd_generation",
        system_prompt="You are a participant in a group discussion.",
        user_prompt="TOPIC: Universal Basic Income\nPARTICIPANT: Jane\nSTANCE: FOR\nTASK: Provide a one-sentence opening statement.",
        max_output_tokens=50
    )
    
    print("Generating response...")
    try:
        result = backend.generate(req)
        print("--- RESULT ---")
        print(result.text)
        print(f"Latency: {result.latency_seconds:.2f}s")
        print("--------------")
        print("SUCCESS")
    except Exception as e:
        print(f"FAILED TO GENERATE: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run()
