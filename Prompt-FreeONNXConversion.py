from ultralytics import YOLOE

# Load the PyTorch model
model = YOLOE("yoloe-11s-seg-pf.pt")

# Export model as .onnx format with specified resolution (must be a multiple of 32)
model.export(format="onnx", imgsz=320)