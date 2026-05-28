"""
Module for model inference
"""
import numpy as np
from pathlib import Path
from typing import Tuple, List, Dict
import tensorflow as tf
import warnings
warnings.filterwarnings('ignore')


class ModelInference:
    """Handle model loading and inference"""
    
    def __init__(self, model_path: str, num_classes: int = None,
                 soc_gap_config: Dict = None):
        """
        Initialize model inference
        
        Args:
            model_path: Path to the model file
            num_classes: Number of output classes
            soc_gap_config: Final-conv tensor/zero-point for SoC-style GAP output
        """
        self.model_path = model_path
        self.model = None
        self.model_type = None
        self.num_classes = num_classes
        self.is_loaded = False
        self.input_details = None
        self.output_details = None
        self.soc_gap_config = soc_gap_config or {}
        self.latest_soc_logits = None
    
    def load_model(self) -> bool:
        """
        Load pre-trained model
        
        Returns:
            True if successful, False otherwise
        """
        try:
            print(f"Loading model from: {self.model_path}")

            if Path(self.model_path).suffix.lower() == ".tflite":
                interpreter_kwargs = {"model_path": self.model_path}
                if self.soc_gap_config:
                    interpreter_kwargs["experimental_preserve_all_tensors"] = True
                self.model = tf.lite.Interpreter(**interpreter_kwargs)
                self.model.allocate_tensors()
                self.input_details = self.model.get_input_details()
                self.output_details = self.model.get_output_details()
                self.model_type = "tflite"
                print("Model loaded successfully (TFLite)")
            else:
                self.model = tf.keras.models.load_model(self.model_path)
                self.model_type = "keras"
                print("Model loaded successfully (TensorFlow/Keras)")
            
            self.is_loaded = True
            
            # Get model information
            self._print_model_info()
            return True
            
        except Exception as e:
            print(f"Error loading model: {e}")
            return False
    
    def predict(self, input_tensor: np.ndarray) -> np.ndarray:
        """
        Run inference on input tensor
        
        Args:
            input_tensor: Input tensor (batch_size, height, width, channels)
            
        Returns:
            Model output predictions
        """
        if not self.is_loaded or self.model is None:
            raise RuntimeError("Model not loaded. Call load_model() first.")
        
        try:
            if self.model_type == "tflite":
                input_detail = self.input_details[0]
                expected_dtype = input_detail["dtype"]
                expected_shape = input_detail["shape"]

                if (len(expected_shape) == 4 and expected_shape[1] == 3
                        and expected_shape[-1] != 3 and input_tensor.shape[-1] == 3):
                    input_tensor = np.transpose(input_tensor, (0, 3, 1, 2))

                if input_tensor.dtype != expected_dtype:
                    input_tensor = input_tensor.astype(expected_dtype)

                self.model.set_tensor(input_detail["index"], input_tensor)
                self.model.invoke()

                if self.soc_gap_config:
                    return self._predict_soc_gap_probs()

                output_detail = self.output_details[0]
                predictions = self.model.get_tensor(output_detail["index"])
                return self._dequantize_output(predictions, output_detail)

            return self.model.predict(input_tensor, verbose=0)
        except Exception as e:
            print(f"Error during prediction: {e}")
            return None
    
    def get_top_predictions(self, predictions: np.ndarray, 
                          top_k: int = 5) -> List[Tuple[int, float]]:
        """
        Get top K predictions with their confidence scores
        
        Args:
            predictions: Model output predictions
            top_k: Number of top predictions to return
            
        Returns:
            List of (class_id, confidence) tuples sorted by confidence
        """
        if predictions is None or len(predictions) == 0:
            return []
        
        # Get first sample if batch
        if len(predictions.shape) > 1:
            pred = predictions[0]
        else:
            pred = predictions
        
        # Match firmware argmax tie-breaking: lower class id wins equal scores.
        top_indices = np.lexsort((np.arange(pred.size), -pred))[:top_k]
        top_values = pred[top_indices]
        
        results = [(int(idx), float(conf)) for idx, conf in zip(top_indices, top_values)]
        
        return results
    
    def format_results(self, top_predictions: List[Tuple[int, float]], 
                      class_labels: List[str] = None) -> List[Dict]:
        """
        Format predictions for display
        
        Args:
            top_predictions: List of (class_id, confidence) tuples
            class_labels: Optional list of class label names
            
        Returns:
            List of formatted result dictionaries
        """
        results = []
        
        for rank, (class_id, confidence) in enumerate(top_predictions, 1):
            result = {
                'rank': rank,
                'class_id': class_id,
                'confidence': confidence,
                'percentage': confidence * 100,
                'label': class_labels[class_id] if class_labels and class_id < len(class_labels) else f'Class {class_id}'
            }
            results.append(result)
        
        return results
    
    def _print_model_info(self):
        """Print model information"""
        if self.model is None:
            return
        
        print("\n=== Model Information ===")
        print(f"Model type: {self.model_type}")

        if self.model_type == "tflite":
            input_detail = self.input_details[0]
            output_detail = self.output_details[0]
            print(f"Input shape: {input_detail['shape']}")
            print(f"Input dtype: {input_detail['dtype']}")
            print(f"Input quantization: {input_detail['quantization']}")
            print(f"Output shape: {output_detail['shape']}")
            print(f"Output dtype: {output_detail['dtype']}")
            print(f"Output quantization: {output_detail['quantization']}")
            if self.soc_gap_config:
                print("Host output mode: SoC GAP logits")
                print(f"SoC GAP tensor index: {self.soc_gap_config.get('tensor_index')}")
                print(f"SoC GAP zero point: {self.soc_gap_config.get('zero_point')}")
        else:
            # Print input shape
            if hasattr(self.model, 'input_shape'):
                print(f"Input shape: {self.model.input_shape}")

            # Print output shape
            if hasattr(self.model, 'output_shape'):
                print(f"Output shape: {self.model.output_shape}")

            # Print number of parameters
            if hasattr(self.model, 'count_params'):
                print(f"Total parameters: {self.model.count_params():,}")
        
        print("========================\n")

    def get_input_quantization(self) -> Tuple[float, int, np.dtype]:
        """Return input scale, zero-point, and dtype for a loaded TFLite model."""
        if self.model_type != "tflite" or not self.input_details:
            return 1.0, 0, np.float32

        input_detail = self.input_details[0]
        scale, zero_point = input_detail["quantization"]
        return float(scale), int(zero_point), np.dtype(input_detail["dtype"])

    def get_input_shape(self) -> Tuple[int, ...]:
        """Return the first input tensor shape for a loaded model."""
        if self.model_type == "tflite" and self.input_details:
            return tuple(int(dim) for dim in self.input_details[0]["shape"])

        if hasattr(self.model, "input_shape"):
            return tuple(int(dim) if dim is not None else -1 for dim in self.model.input_shape)

        raise RuntimeError("Input shape is unavailable because the model is not loaded")

    def _dequantize_output(self, output: np.ndarray, output_detail: Dict) -> np.ndarray:
        """Convert quantized output back to float scores for display."""
        if output.dtype not in (np.int8, np.uint8):
            return output

        scale, zero_point = output_detail["quantization"]
        if scale == 0:
            return output.astype(np.float32)

        return (output.astype(np.float32) - zero_point) * scale

    def _predict_soc_gap_probs(self) -> np.ndarray:
        """Match firmware: GAP over final conv output, then softmax for display."""
        tensor_index = int(self.soc_gap_config["tensor_index"])
        zero_point = int(self.soc_gap_config["zero_point"])

        tensor = self.model.get_tensor(tensor_index).astype(np.int32)
        centered = tensor - zero_point

        if centered.ndim == 4:
            sums = centered.sum(axis=(1, 2))
            denominator = int(centered.shape[1] * centered.shape[2])
            logits = self._trunc_divide(sums, denominator)
        elif centered.ndim == 2:
            logits = centered
        else:
            logits = centered.reshape((centered.shape[0], -1))

        self.latest_soc_logits = logits.astype(np.int32)
        return self._softmax_logits(self.latest_soc_logits)

    @staticmethod
    def _trunc_divide(values: np.ndarray, denominator: int) -> np.ndarray:
        """Integer division with C semantics, matching firmware for negatives."""
        return np.where(
            values >= 0,
            values // denominator,
            -((-values) // denominator),
        ).astype(np.int32)

    @staticmethod
    def _softmax_logits(logits: np.ndarray) -> np.ndarray:
        logits_float = logits.astype(np.float32)
        shifted = logits_float - np.max(logits_float, axis=-1, keepdims=True)
        shifted = np.maximum(shifted, -80.0)
        exps = np.exp(shifted)
        totals = np.sum(exps, axis=-1, keepdims=True)
        return exps / np.maximum(totals, np.finfo(np.float32).tiny)
    
    def unload(self):
        """Unload model to free memory"""
        if self.model is not None:
            del self.model
            self.model = None
            self.model_type = None
            self.input_details = None
            self.output_details = None
            self.is_loaded = False
            print("Model unloaded")
