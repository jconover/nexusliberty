package io.devopsnexus.nexusapp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;
import java.lang.management.ThreadMXBean;

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

    @Test
    void call_returnsDown_whenHeapExceedsThreshold() {
        ThreadMXBean threadBean = mock(ThreadMXBean.class);
        MemoryMXBean memoryBean = mock(MemoryMXBean.class);
        // Simulate 96% heap usage (above 95% threshold)
        when(threadBean.findDeadlockedThreads()).thenReturn(null);
        when(threadBean.getThreadCount()).thenReturn(10);
        when(memoryBean.getHeapMemoryUsage())
                .thenReturn(new MemoryUsage(-1, 960 * 1024 * 1024L, 1000 * 1024 * 1024L, 1000 * 1024 * 1024L));

        LivenessCheck testCheck = new LivenessCheck() {
            @Override ThreadMXBean getThreadMXBean() { return threadBean; }
            @Override MemoryMXBean getMemoryMXBean() { return memoryBean; }
        };

        HealthCheckResponse response = testCheck.call();

        assertEquals(HealthCheckResponse.Status.DOWN, response.getStatus());
        assertTrue(response.getData().isPresent());
        assertNotNull(response.getData().get().get("reason"));
    }

    @Test
    void call_returnsDown_whenDeadlockDetected() {
        ThreadMXBean threadBean = mock(ThreadMXBean.class);
        MemoryMXBean memoryBean = mock(MemoryMXBean.class);
        // Simulate deadlock with healthy heap
        when(threadBean.findDeadlockedThreads()).thenReturn(new long[]{1L, 2L});
        when(memoryBean.getHeapMemoryUsage())
                .thenReturn(new MemoryUsage(-1, 100 * 1024 * 1024L, 1000 * 1024 * 1024L, 1000 * 1024 * 1024L));

        LivenessCheck testCheck = new LivenessCheck() {
            @Override ThreadMXBean getThreadMXBean() { return threadBean; }
            @Override MemoryMXBean getMemoryMXBean() { return memoryBean; }
        };

        HealthCheckResponse response = testCheck.call();

        assertEquals(HealthCheckResponse.Status.DOWN, response.getStatus());
        assertTrue(response.getData().isPresent());
        assertEquals(2L, response.getData().get().get("deadlockedThreads"));
    }
}
