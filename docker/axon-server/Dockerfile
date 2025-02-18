FROM openjdk:17-slim
WORKDIR /app
COPY axon-server.jar ./
EXPOSE 8024 8124
ENTRYPOINT ["java", "-jar", "axon-server.jar"]
