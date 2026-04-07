package io.devopsnexus.nexusapp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.lang.reflect.Field;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class InfoResourceTest {

    private InfoResource resource;

    @BeforeEach
    void setUp() throws Exception {
        resource = new InfoResource();
        Field versionField = InfoResource.class.getDeclaredField("appVersion");
        versionField.setAccessible(true);
        versionField.set(resource, "1.0.0");
    }

    @Test
    void info_returnsAppName() {
        Map<String, String> result = resource.info();

        assertEquals("NexusLiberty", result.get("app"));
    }

    @Test
    void info_returnsDescription() {
        Map<String, String> result = resource.info();

        assertEquals("Enterprise Middleware Modernization Platform", result.get("description"));
    }

    @Test
    void info_returnsJavaVersion() {
        Map<String, String> result = resource.info();

        assertNotNull(result.get("javaVersion"));
        assertEquals(System.getProperty("java.version", "Unknown"), result.get("javaVersion"));
    }

    @Test
    void info_returnsRuntimeName() {
        Map<String, String> result = resource.info();

        assertNotNull(result.get("runtime"));
    }
}
