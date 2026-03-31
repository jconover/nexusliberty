package io.devopsnexus.nexusapp;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import io.restassured.RestAssured;
import io.restassured.http.ContentType;

/**
 * Integration tests for NexusLiberty JAX-RS endpoints.
 * Runs against a Liberty server started by the liberty-maven-plugin.
 */
class EndpointIT {

    @BeforeAll
    static void setup() {
        String port = System.getProperty("http.port", "9080");
        RestAssured.baseURI = "http://localhost";
        RestAssured.port = Integer.parseInt(port);
        RestAssured.basePath = "/app/api";
    }

    // ── HealthResource tests ────────────────────────────────────────

    @Test
    void healthEndpoint_returnsOk() {
        given()
            .accept(ContentType.JSON)
        .when()
            .get("/health")
        .then()
            .statusCode(200)
            .contentType(ContentType.JSON)
            .body("status", equalTo("UP"))
            .body("app", equalTo("NexusLiberty"))
            .body("version", equalTo("1.0.0"));
    }

    // ── InfoResource tests ──────────────────────────────────────────

    @Test
    void infoEndpoint_returnsOk() {
        given()
            .accept(ContentType.JSON)
        .when()
            .get("/info")
        .then()
            .statusCode(200)
            .contentType(ContentType.JSON)
            .body("app", equalTo("NexusLiberty"))
            .body("description", equalTo("Enterprise Middleware Modernization Platform"))
            .body("version", equalTo("1.0.0"))
            .body("runtime", notNullValue())
            .body("javaVersion", notNullValue());
    }

    @Test
    void infoEndpoint_returnsJsonContentType() {
        given()
        .when()
            .get("/info")
        .then()
            .statusCode(200)
            .contentType(ContentType.JSON);
    }

    @Test
    void healthEndpoint_returnsJsonContentType() {
        given()
        .when()
            .get("/health")
        .then()
            .statusCode(200)
            .contentType(ContentType.JSON);
    }
}
