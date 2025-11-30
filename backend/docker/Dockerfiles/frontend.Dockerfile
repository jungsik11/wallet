# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /app

# Upgrade pip
RUN pip install --no-cache-dir -U pip

# Copy and install the requirements
COPY backend/mcp/frontend/requirements.txt /app/
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy the application code into the container
COPY backend/mcp/frontend/ /app/

# Copy the frontend source code needed for indexing into a specific directory
COPY frontend/app/lib/ /app/frontend_src/

# Run the indexer to build the vector store.
# This will download the embedding model and create the 'vector_store' directory inside /app.
RUN python /app/indexer.py

# Set the command to run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3001"]
