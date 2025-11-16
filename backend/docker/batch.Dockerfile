# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file for the batch job
COPY ./docker/batch-requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r batch-requirements.txt

# Copy the rest of the backend application code into the container
# The build context should be the 'backend' directory
COPY . .

# Command to run the batch application
# Note: Environment variables (KIS_ID, KIS_ACNT, etc.) must be passed at runtime
# Example: docker run --env-file .env batch-app
CMD ["python", "app.py"]
