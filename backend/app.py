from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer, util
from typing import List, Dict, Any
import json
import torch

app = FastAPI(title="PlaceMate Recommender")

# -----------------------------
# Load model & data at startup
# -----------------------------
MODEL_NAME = "st_place_embed_model_triplet"
model = SentenceTransformer(MODEL_NAME)

with open("artifacts/places.json", "r", encoding="utf-8") as f:
    ALL_PLACES: List[Dict[str, Any]] = json.load(f)

# Build list of places that have clean_texts
place_texts: List[str] = []
place_meta: List[Dict[str, Any]] = []  # keep original metadata aligned with embeddings

for p in ALL_PLACES:
    ct = p.get("clean_texts", [])
    if not ct:
        continue
    place_texts.append(" ".join(ct))
    place_meta.append({
        "name": p.get("name") or p.get("place_id"),
        "address": p.get("address", ""),
        "place_id": p.get("place_id")
    })

# Encode all places once (normalized vectors for cosine sim)
# NOTE: This uses CPU by default; if you have CUDA, you can: model = model.to("cuda")
place_embs: torch.Tensor = model.encode(
    place_texts,
    convert_to_tensor=True,
    normalize_embeddings=True,
    show_progress_bar=False
)  # shape: (N, 384)

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": MODEL_NAME,
        "num_places": len(place_meta),
        "embedding_dim": int(place_embs.shape[-1]),
        "device": str(place_embs.device)
    }

# -----------------------------
# API
# -----------------------------
class Query(BaseModel):
    text: str
    top_k: int = 5

@app.post("/recommend")
def recommend(query: Query):
    text = (query.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Empty query")

    if len(place_meta) == 0:
        raise HTTPException(status_code=503, detail="No places with clean_texts loaded")

    # Encode query and compute cosine similarities in one shot
    q_emb: torch.Tensor = model.encode(
        text,
        convert_to_tensor=True,
        normalize_embeddings=True
    )  # shape: (384,) or (1, 384)

    # util.cos_sim expects (1, d) vs (N, d); returns (1, N)
    sims: torch.Tensor = util.cos_sim(q_emb, place_embs)[0]  # shape: (N,)

    # Clamp top_k into range
    top_k = max(1, min(int(query.top_k), len(place_meta)))

    # Fast top-k
    values, indices = torch.topk(sims, k=top_k, largest=True)

    results = []
    for score, idx in zip(values.tolist(), indices.tolist()):
        meta = place_meta[idx]
        results.append({
            "name": meta["name"],
            "address": meta["address"],
            "score": float(score),
        })

    return {"query": text, "results": results}
