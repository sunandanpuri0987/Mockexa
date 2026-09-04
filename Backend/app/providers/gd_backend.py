import logging
import time
from pathlib import Path
from typing import Optional

from app.providers.llm_backend import (
    GenerationRequest,
    GenerationResult,
    LLMBackend,
    LLMBackendError,
)

logger = logging.getLogger(__name__)

class LocalQwenBackend(LLMBackend):
    """
    Local backend that loads Qwen2.5-1.5B-Instruct and a specific LoRA adapter
    for Group Discussion generation.
    """
    _instance: Optional['LocalQwenBackend'] = None
    
    @classmethod
    def get_instance(cls, model_dir: Path, base_model_name: str = "Qwen/Qwen2.5-1.5B-Instruct") -> 'LocalQwenBackend':
        if cls._instance is None:
            cls._instance = cls(model_dir, base_model_name)
        return cls._instance

    def __init__(self, model_dir: Path, base_model_name: str = "Qwen/Qwen2.5-1.5B-Instruct"):
        try:
            import torch
            from peft import PeftModel
            from transformers import AutoModelForCausalLM, AutoTokenizer
        except ImportError as e:
            raise RuntimeError(
                "Missing ML dependencies for LocalQwenBackend. "
                "Ensure torch, transformers, peft, accelerate are installed."
            ) from e

        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        logger.info(f"Loading local Qwen backend on {self.device}...")

        # Load tokenizer
        self.tokenizer = AutoTokenizer.from_pretrained(base_model_name)
        
        # Load base model
        logger.info(f"Loading base model {base_model_name}")
        base_model = AutoModelForCausalLM.from_pretrained(
            base_model_name,
            torch_dtype=torch.float16 if self.device == "cuda" else torch.float32,
            device_map="auto" if self.device == "cuda" else None,
        )
        
        # Load LoRA adapter
        logger.info(f"Loading LoRA adapter from {model_dir}")
        self.model = PeftModel.from_pretrained(base_model, str(model_dir))
        
        # Set up generation parameters
        self.terminators = [
            self.tokenizer.eos_token_id,
            self.tokenizer.convert_tokens_to_ids("<|im_end|>")
        ]
        
        self.provider_name = "local"
        self.model_name = f"{base_model_name} + lora"
        
        logger.info("Local Qwen backend loaded successfully.")

    def generate(self, request: GenerationRequest) -> GenerationResult:
        import torch
        start_time = time.monotonic()
        
        messages = [
            {"role": "system", "content": request.system_prompt},
            {"role": "user", "content": request.user_prompt}
        ]
        
        try:
            text_input = self.tokenizer.apply_chat_template(
                messages, 
                tokenize=False, 
                add_generation_prompt=True
            )
            inputs = self.tokenizer(text_input, return_tensors="pt").to(self.model.device)
            
            with torch.no_grad():
                outputs = self.model.generate(
                    **inputs,
                    max_new_tokens=request.max_output_tokens,
                    eos_token_id=self.terminators,
                    do_sample=True,
                    temperature=0.7,
                    top_p=0.9
                )
                
            input_length = inputs.input_ids.shape[-1]
            generated_ids = outputs[0][input_length:]
            response_text = self.tokenizer.decode(generated_ids, skip_special_tokens=True)
            
            latency = time.monotonic() - start_time
            
            return GenerationResult(
                text=response_text,
                provider=self.provider_name,
                model=self.model_name,
                input_tokens=input_length,
                output_tokens=len(generated_ids),
                latency_seconds=latency,
                retry_count=0
            )
            
        except Exception as e:
            logger.error(f"Local Qwen generation failed: {e}")
            raise LLMBackendError(f"Local generation failed: {e}") from e
