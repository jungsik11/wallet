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
                outer_json_response = loads(response_text)
                
                # Check for the structure with 'ok' and a nested 'data' field containing another JSON string
                if outer_json_response.get("ok") and "data" in outer_json_response and isinstance(outer_json_response["data"], dict):
                    if outer_json_response["data"].get("success") is False:
                        logging.error(f"MCP tool reported failure. Full outer_json_response: {outer_json_response}")
                    
                    if "data" in outer_json_response["data"] and isinstance(outer_json_response["data"]["data"], str):
                        inner_json_string = outer_json_response["data"]["data"]
                        return loads(inner_json_string) # Parse the inner JSON string
                    else:
                        # If it's not the double-encoded format, return the outer parsed JSON directly
                        return outer_json_response
        except Exception as e:
            logging.error(f"Error calling MCP tool '{tool_name}' on attempt {attempt + 1}: {e}")
            if attempt < max_retries - 1:
                await asyncio.sleep(retry_delay)
            else:
                traceback.print_exc()
                raise HTTPException(status_code=500, detail=f"Error calling MCP tool '{tool_name}' after {max_retries} attempts: {e}")
