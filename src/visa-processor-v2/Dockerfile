FROM maven as builder 

COPY . /usr/src/poc
WORKDIR /usr/src/poc
RUN mvn clean && mvn package

FROM gcr.io/distroless/java17-debian11

USER 1001

COPY --from=builder /usr/src/poc/target/webapp-1.0-jar-with-dependencies.jar /deployments/webapp-1.0-jar-with-dependencies.jar

ENTRYPOINT
