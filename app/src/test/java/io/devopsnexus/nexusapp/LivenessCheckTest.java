package io.devopsnexus.nexusapp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.eclipse.microprofile.health.HealthCheckResponse;
import org.junit.jupiter.api.Test;

class LivenessCheckTest {

    private final LivenessCheck check = new LivenessCheck();

    @Test
    void call_returnsUp_whenHealthy() {
        HealthCheckResponse response = check.call();

        assertEquals("nexusliberty-liveness", response.getName());
        assertEquals(HealthCheckResponse.Status.UP, response.getStatus());
        assertTrue(response.getData().isPresent());
        assertNotNull(response.getData().get().get("threadCount"));
        assertNotNull(response.getData().get().get("heapUsedMB"));
        assertNotNull(response.getData().get().get("heapMaxMB"));
        assertNotNull(response.getData().get().get("heapUsagePercent"));
    }

    @Test
    void call_reportsHeapMetrics() {
        HealthCheckResponse response = check.call();

        long heapUsedMB = (Long) response.getData().get().get("heapUsedMB");
        long heapMaxMB = (Long) response.getData().get().get("heapMaxMB");
        assertTrue(heapUsedMB > 0, "Heap used should be positive");
        assertTrue(heapMaxMB > 0, "Heap max should be positive");
    }
}
