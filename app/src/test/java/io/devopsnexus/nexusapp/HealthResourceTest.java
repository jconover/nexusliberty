package io.devopsnexus.nexusapp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.lang.reflect.Field;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class HealthResourceTest {

    private HealthResource resource;

    @BeforeEach
    void setUp() throws Exception {
        resource = new HealthResource();
        Field versionField = HealthResource.class.getDeclaredField("appVersion");
        versionField.setAccessible(true);
        versionField.set(resource, "1.0.0");
    }

    @Test
    void health_returnsUpStatus() {
        Map<String, String> result = resource.health();

        assertEquals("UP", result.get("status"));
    }

    @Test
    void health_returnsAppName() {
        Map<String, String> result = resource.health();

        assertEquals("NexusLiberty", result.get("app"));
    }

    @Test
    void health_returnsVersion() {
        Map<String, String> result = resource.health();

        assertEquals("1.0.0", result.get("version"));
    }
}
