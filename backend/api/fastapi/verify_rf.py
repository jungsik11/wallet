import asyncio
import logging
import sys
import os

# Add current directory to path so we can import app
sys.path.append(os.getcwd())

async def verify():
    from app import get_kr_risk_free_rate_v2
    print("--- Starting Verification ---")
    try:
        rate = await get_kr_risk_free_rate_v2()
        print(f"RESULT: get_kr_risk_free_rate() returned {rate}")
        print(f"Percentage form: {rate * 100}%")
    except Exception as e:
        print(f"ERROR: {e}")
    print("--- End Verification ---")

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(verify())
