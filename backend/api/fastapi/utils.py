import os
import traceback
from json import loads
from typing import Any, Dict, List
import logging
import asyncio

from fastapi import HTTPException
from pydantic import BaseModel
from fastmcp import Client

# MCP Server URLs
MCP_STOCK_SERVER_URL = "http://kis-trade-mcp-stock:3000"
MCP_PENSION_SERVER_URL = "http://kis-trade-mcp-pension:3000"

# --- Pydantic Models ---

class StockHolding(BaseModel):
    """Model for individual stock holdings."""
    yearly_profit: Dict[str, float]
    holdings: Dict[str, Any]

class ProfitResponse(BaseModel):
    """Response model for overall profit calculation."""
    yearly_total_profit: Dict[str, float]
    stocks: List[StockHolding]

async def call_mcp_tool(server_url: str, tool_name: str, api_type: str, params: dict) -> Dict[str, Any]:
    """Helper function to call a tool on the MCP server with retries."""
    max_retries = 5
    retry_delay = 2  # seconds
    for attempt in range(max_retries):
        try:
            async with Client(f"{server_url}/sse") as client:
                result = await client.call_tool(tool_name, {"api_type": api_type, "params": params})
                response_text = result.content[0].text
                logging.error(f"[DEBUG] [UTILS] Raw response: {response_text}")
                outer_json_response = loads(response_text)
                # Normalize response to a dictionary if it's a single-item list
                if isinstance(outer_json_response, list) and len(outer_json_response) > 0:
                    outer_json_response = outer_json_response[0]
                
                # Check for the structure with 'ok' and a nested 'data' field
                if isinstance(outer_json_response, dict) and outer_json_response.get("ok") and "data" in outer_json_response:
                    data_payload = outer_json_response["data"]
                    if isinstance(data_payload, dict) and "data" in data_payload and isinstance(data_payload["data"], str):
                        # Case: Double-encoded JSON (data field contains a JSON string)
                        try:
                            decoded_data = loads(data_payload["data"])
                            return decoded_data
                        except:
                            return data_payload["data"]
                    elif isinstance(data_payload, dict):
                        # Case: Data payload is a direct dictionary
                        return data_payload
                    elif isinstance(data_payload, list):
                        # Case: Data payload is a list. Wrap it in a dictionary for consistency.
                        logging.warning(f"MCP tool '{tool_name}' returned a list as direct data payload. Wrapping in 'data_list' key. Payload: {data_payload}")
                        return {"data_list": data_payload}
                
                # If 'ok' is false, or 'data' is missing/not as expected
                logging.error(f"MCP tool '{tool_name}' returned unexpected response structure: {outer_json_response}")
                raise ValueError("Unexpected response structure from MCP tool.")

        except Exception as e:
            logging.error(f"Error calling MCP tool '{tool_name}' on attempt {attempt + 1}: {e}")
            if attempt < max_retries - 1:
                await asyncio.sleep(retry_delay)
            else:
                traceback.print_exc()
                raise HTTPException(status_code=500, detail=f"Error calling MCP tool '{tool_name}' after {max_retries} attempts: {e}")
    # This part should ideally not be reached if exceptions are always raised
    return {} # Default return for type hinting and safety
