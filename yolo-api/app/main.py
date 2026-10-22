import os
import shutil
import uuid
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from app.detector import process_video

app = FastAPI(
    title="YOLOE Video Detection API"
)


@app.get("/")
def home():
    return {
        "message": "YOLOE API is running"
    }


@app.get("/models")
def get_models():
    return {
        "models": [
            "small",
            "medium",
            "large"
        ]
    }


@app.post("/detect")
async def detect(
    model: str = Form(...),
    video: UploadFile = File(...)
):

    job_id = str(uuid.uuid4().hex[:8])

    input_path = f"uploads/{job_id}.mp4"
    output_path = f"outputs/{job_id}.mp4"

    # Save uploaded video
    with open(input_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)

    try:

        process_video(
            input_path,
            output_path,
            model
        )

    except Exception as e:
        print("ERROR TYPE:", type(e).__name__)
        print("ERROR MESSAGE:", repr(e))

        raise HTTPException(
         status_code=500,
         detail=f"{type(e).__name__}: {repr(e)}"
     )

    return FileResponse(
        output_path,
        media_type="video/mp4",
        filename="detected_video.mp4"
    )