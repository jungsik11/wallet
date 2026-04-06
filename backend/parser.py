
import sys
from bs4 import BeautifulSoup
import pandas as pd

# The HTML content is passed as a command-line argument
html_content = sys.argv[1]

soup = BeautifulSoup(html_content, 'html.parser')

# Find the table containing the data
# Based on inspection of the website, the table is the first one
table = soup.find('table', {'class': 'table-blue-alternating-rows'})

# Check if the table is found
if table:
    # Use pandas to read the HTML table
    df = pd.read_html(str(table))[0]

    # The columns are Ticker, Company, Rank, Market Cap ($B), and some others
    # We need Ticker, Company, and Market Cap
    df = df[['Ticker', 'Company', 'Market Cap ($B)']]

    # Convert Market Cap from Billions to Trillions
    df['MarketCap_Trillion'] = pd.to_numeric(df['Market Cap ($B)'].replace({'\$': '', ',': ''}, regex=True)) / 1000

    # Filter for companies with market cap >= $1 Trillion
    df = df[df['MarketCap_Trillion'] >= 1.0]
    
    # Rename columns to match the existing file
    df = df.rename(columns={'Company': 'Name'})

    # Select and reorder columns
    df = df[['Ticker', 'Name', 'MarketCap_Trillion']]

    # Print the data in CSV format, without the index
    print(df.to_csv(index=False))

else:
    print("Error: Table not found.", file=sys.stderr)
    sys.exit(1)
