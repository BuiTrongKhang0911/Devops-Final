FROM eclipse-temurin:21-jdk-alpine AS builder

WORKDIR /app

# Copy Maven files
COPY pom.xml .
COPY src ./src

# Download dependencies
RUN apk add --no-cache maven && \
    mvn dependency:go-offline -B

# Build the application
RUN mvn package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Update Alpine packages to fix CVEs (libexpat, zlib, etc.)
RUN apk upgrade --no-cache

# Create uploads directory
RUN mkdir -p /app/uploads

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
