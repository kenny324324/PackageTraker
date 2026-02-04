from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from enum import Enum
from typing import Optional
import parcel_tw

app = FastAPI(
    title="PackageTraker API",
    description="台灣物流追蹤 API",
    version="1.0.0"
)

# CORS 設定（允許 iOS App 存取）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Platform(str, Enum):
    seven_eleven = "seven_eleven"
    family_mart = "family_mart"
    okmart = "okmart"
    shopee = "shopee"

# parcel-tw 的 platform 對應
PLATFORM_MAP = {
    Platform.seven_eleven: parcel_tw.Platform.SevenEleven,
    Platform.family_mart: parcel_tw.Platform.FamilyMart,
    Platform.okmart: parcel_tw.Platform.OKMart,
    Platform.shopee: parcel_tw.Platform.Shopee,
}

@app.get("/")
async def root():
    return {"status": "ok", "message": "PackageTraker API"}

@app.get("/api/track")
async def track_package(
    order_id: str = Query(..., description="物流單號"),
    platform: Platform = Query(..., description="物流平台")
):
    """
    追蹤包裹狀態

    - **order_id**: 物流單號
    - **platform**: 物流平台 (seven_eleven, family_mart, okmart, shopee)
    """
    try:
        # 使用 parcel-tw 追蹤
        pt_platform = PLATFORM_MAP[platform]
        result = parcel_tw.track(pt_platform, order_id)

        if result is None:
            raise HTTPException(status_code=404, detail="查無此單號")

        return {
            "success": True,
            "data": {
                "order_id": result.order_id,
                "platform": platform.value,
                "status": result.status,
                "time": str(result.time) if result.time else None,
                "is_delivered": result.is_delivered,
                "raw_data": getattr(result, 'raw_data', None)
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/health")
async def health_check():
    return {"status": "healthy"}
