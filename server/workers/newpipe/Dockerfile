# NewPipe Extractor JVM worker — co-equal fallback for incomplete yt-dlp dumps.
FROM eclipse-temurin:17-jdk-jammy AS build
WORKDIR /src
COPY settings.gradle.kts build.gradle.kts ./
COPY src ./src
RUN apt-get update && apt-get install -y --no-install-recommends unzip \
 && curl -fsSL https://services.gradle.org/distributions/gradle-8.10.2-bin.zip -o /tmp/gradle.zip \
 && unzip -q /tmp/gradle.zip -d /opt \
 && /opt/gradle-8.10.2/bin/gradle --no-daemon jar \
 && rm -rf /tmp/gradle.zip /var/lib/apt/lists/*

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
RUN useradd -m -u 10001 yxz
COPY --from=build /src/build/libs/*.jar /app/newpipe.jar
RUN chown yxz:yxz /app/newpipe.jar
ENV NEWPIPE_PORT=8091
EXPOSE 8091
USER yxz
CMD ["java", "-jar", "/app/newpipe.jar"]
