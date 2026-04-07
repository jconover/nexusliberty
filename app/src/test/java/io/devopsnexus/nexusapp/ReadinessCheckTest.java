package io.devopsnexus.nexusapp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.eclipse.microprofile.health.HealthCheckResponse;
import org.junit.jupiter.api.Test;

class ReadinessCheckTest {

    @Test
    void call_returnsDown_whenServletContextNull() {
        ReadinessCheck check = new ReadinessCheck();
        // ServletContext is null (not injected in unit test context)
        HealthCheckResponse response = check.call();

        assertEquals("nexusliberty-readiness", response.getName());
        assertEquals(HealthCheckResponse.Status.DOWN, response.getStatus());
        assertTrue(response.getData().isPresent());
        assertEquals("unavailable", response.getData().get().get("servletContext"));
    }
}
