FROM mcr.microsoft.com/dotnet/sdk:8.0

# Install system dependencies: curl, git, jq, and Node.js 20.x
RUN apt-get update -y && \
    apt-get install -y curl git jq && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Add dotnet tools to PATH
ENV PATH="$PATH:/root/.dotnet/tools"

# Set working directory
WORKDIR /app

# Copy package files and install dependencies
RUN mkdir /app/__tests__
COPY __tests__/package*.json ./__tests__/
RUN npm --prefix /app/__tests__ ci

# Install GitVersion as a global dotnet tool
RUN dotnet tool install GitVersion.Tool --version 5.12.0 --create-manifest-if-needed

# Copy the full monotools repo (adjust path if needed)
COPY __tests__ /app/__tests__
COPY semver-yeasy.sh /app/

# Set environment variables for test tools if needed
ENV JQ_EXEC_PATH=jq
ENV GITVERSION_EXEC_PATH='dotnet dotnet-gitversion'

# Run the tests
RUN npm --prefix /app/__tests__ t -- --verbose

CMD [ "tail", "-f", "/dev/null" ]
