from fastmcp import Client
import asyncio

async def main():
    # Connect via stdio to a local script (replace "my_server.py" with your actual server script or URL)
    # For demonstration, we'll assume a local server setup.
    async with Client("http://localhost:3001/sse") as client:
        print("Connected to fastmcp client.")

        # Call the overseas_stock tool to inquire about balance
        # The parameters are passed as a dictionary to the call_tool method
        result = await client.call_tool(
            "overseas_stock",
            {
                "api_type": "inquire_balance",
                "params": {
                    "env_dv": "real",
                    "ovrs_excg_cd": "NASD",
                    "tr_crcy_cd": "USD"
                }
            }
        )
        print(f"Overseas Stock Balance Result: {result.content[0].text}")

if __name__ == "__main__":
    asyncio.run(main())
